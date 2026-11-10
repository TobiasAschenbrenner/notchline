import AppKit
import SwiftUI

typealias ViewState<Value> = SwiftUI.State<Value>

struct NotchContour: Shape {
    var shoulder: CGFloat
    var corner: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(shoulder, corner) }
        set { shoulder = newValue.first; corner = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let s = min(shoulder, h * 0.34)
        let r = min(corner, (h - s) * 0.7)
        let edge = w - s
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: w, y: 0))
        path.addCurve(to: CGPoint(x: edge, y: s),
                      control1: CGPoint(x: w - s * 0.58, y: 0), control2: CGPoint(x: edge, y: s * 0.42))
        path.addLine(to: CGPoint(x: edge, y: h - r))
        path.addCurve(to: CGPoint(x: edge - r, y: h),
                      control1: CGPoint(x: edge, y: h - r * 0.33), control2: CGPoint(x: edge - r * 0.33, y: h))
        path.addLine(to: CGPoint(x: s + r, y: h))
        path.addCurve(to: CGPoint(x: s, y: h - r),
                      control1: CGPoint(x: s + r * 0.33, y: h), control2: CGPoint(x: s, y: h - r * 0.33))
        path.addLine(to: CGPoint(x: s, y: s))
        path.addCurve(to: .zero, control1: CGPoint(x: s, y: s * 0.42), control2: CGPoint(x: s * 0.58, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct Waveform: View {
    static let width: CGFloat = 18.6
    var playing: Bool
    var reduceMotion: Bool
    var tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18, paused: !playing || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.4) {
                ForEach(0..<5) { index in
                    Capsule().fill(tint.opacity(0.85))
                        .frame(width: 1.8, height: playing && !reduceMotion
                               ? 3 + abs(sin(time * 5 + Double(index) * 1.21)) * 9
                               : CGFloat([4, 7, 11, 7, 4][index]))
                }
            }
            .frame(width: Self.width, height: 14)
        }
        .accessibilityHidden(true)
    }
}

struct NotchGeometry: Equatable {
    var cameraWidth: CGFloat
    var cameraHeight: CGFloat
    static let preview = NotchGeometry(cameraWidth: 168, cameraHeight: 35)

    var playerWidth: CGFloat { max(352, cameraWidth + 180) }
    var panelWidth: CGFloat { max(playerWidth, NotchHUDMetrics.width(cameraWidth: cameraWidth, hovered: true)) + 32 }
    var panelHeight: CGFloat { 244 }

    func size(for presentation: NotchPresentation) -> CGSize {
        switch presentation {
        case .idle: return CGSize(width: cameraWidth, height: cameraHeight)
        case .compact: return CGSize(width: cameraWidth + 79, height: cameraHeight)
        case .alert(.headphones, _): return size(for: .compact)
        case .alert(_, let hovered):
            return CGSize(width: NotchHUDMetrics.width(cameraWidth: cameraWidth, hovered: hovered),
                          height: cameraHeight + (hovered ? 6 : 0))
        case .peek: return CGSize(width: cameraWidth + 79, height: cameraHeight + 24)
        case .expanded: return CGSize(width: playerWidth, height: 180)
        case .volumeControl: return CGSize(width: playerWidth, height: 212)
        }
    }
}

enum NotchPresentation: Equatable {
    case idle, compact, peek, expanded, volumeControl
    case alert(NotchAlert.Kind, hovered: Bool = false)

    var isPlayer: Bool { self == .expanded || self == .volumeControl }

    var alertKind: NotchAlert.Kind? {
        if case .alert(let kind, _) = self { return kind }
        return nil
    }

    var contour: NotchContour {
        switch self {
        case .idle: return .init(shoulder: 2, corner: 9)
        case .compact, .alert: return .init(shoulder: NotchHUDMetrics.shoulder, corner: NotchHUDMetrics.corner)
        case .peek: return .init(shoulder: 7, corner: 14)
        case .expanded, .volumeControl: return .init(shoulder: 15, corner: 28)
        }
    }

    @MainActor
    init(model: NotchModel) {
        if let alert = model.alert { self = .alert(alert.kind, hovered: model.expanded && alert.value != nil) }
        else if model.expanded { self = model.outputVolumeOpen ? .volumeControl : .expanded }
        else if model.trackPeek { self = .peek }
        else if model.compactMusic { self = .compact }
        else { self = .idle }
    }
}

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaMonitor
    @ObservedObject var signals: SystemSignals
    var geometry: NotchGeometry
    var sample = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var scene: NotchScene?
    @ViewState private var motion: NotchMotion?
    @ViewState private var pulse: NotchLimitPulse?

    var body: some View {
        let target = NotchScene(model: model)
        let displayed = scene ?? target
        let resting = NotchFrame(displayed.presentation, geometry: geometry, alert: displayed.alert)
        TimelineView(.animation(paused: motion == nil && pulse == nil)) { _ in
            notch(currentFrame(resting, alert: displayed.alert))
        }
        .onChange(of: target, initial: true) { old, new in
            if old.alert?.kind != new.alert?.kind { pulse = nil }
            if scene != nil, model.presentationVisible, old.presentation != new.presentation, !reduceMotion {
                let now = ProcessInfo.processInfo.systemUptime
                var start = motion?.frame(at: now) ?? NotchFrame(old.presentation, geometry: geometry, alert: old.alert)
                if let alert = old.alert, alert.kind == start.alert?.kind { start.alert = alert }
                motion = NotchMotion(from: start, to: new, geometry: geometry, at: now)
            }
            scene = new
        }
        .onChange(of: geometry) { motion = nil }
        .onChange(of: model.presentationVisible) { motion = nil; pulse = nil }
        .onChange(of: reduceMotion) { motion = nil; pulse = nil }
        .onChange(of: model.levelLimitAt) { _, timestamp in
            guard let timestamp, model.presentationVisible, !reduceMotion else { return }
            pulse = NotchLimitPulse(startedAt: timestamp, initialWidth: pulse?.width(at: timestamp) ?? 0)
        }
        .task(id: motion?.endsAt) {
            guard let end = motion?.endsAt else { return }
            try? await Task.sleep(for: .seconds(max(0, end - ProcessInfo.processInfo.systemUptime)))
            if !Task.isCancelled { motion = nil }
        }
        .task(id: pulse?.startedAt) {
            guard let pulse else { return }
            let end = pulse.startedAt + NotchLimitPulse.duration
            try? await Task.sleep(for: .seconds(max(0, end - ProcessInfo.processInfo.systemUptime)))
            if !Task.isCancelled { self.pulse = nil }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    private func currentFrame(_ resting: NotchFrame, alert: NotchAlert?) -> NotchFrame {
        let now = ProcessInfo.processInfo.systemUptime
        var frame = motion?.frame(at: now) ?? resting
        if let alert, alert.kind == frame.alert?.kind {
            frame.alert = alert
            if alert.value != nil { frame.size.width += pulse?.width(at: now) ?? 0 }
        }
        return frame
    }

    private func notch(_ frame: NotchFrame) -> some View {
        ZStack(alignment: .top) {
            frame.contour.fill(.black).opacity(frame.shell)
            if frame.player > 0 {
                player(row: frame.volumeRow)
                    .frame(width: geometry.playerWidth)
                    .modifier(NotchDetail(progress: frame.player, blur: 5, y: -8))
                    .allowsHitTesting(frame.player > 0.8)
            }
            if frame.media > 0 { mediaAnchors(frame) }
            if frame.hud > 0, let alert = frame.alert { hud(alert, frame: frame) }
            if frame.peek > 0, let track = model.music {
                Text(track.artist.isEmpty ? track.title : "♪  \(track.title)  ·  \(track.artist)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.73))
                    .lineLimit(1)
                    .padding(.horizontal, 13)
                    .frame(width: geometry.size(for: .peek).width, height: 20)
                    .offset(y: geometry.cameraHeight)
                    .modifier(NotchDetail(progress: frame.peek, y: -4))
            }
        }
        .frame(width: frame.size.width, height: frame.size.height, alignment: .top)
        .clipShape(frame.contour)
        .overlay {
            if model.outline {
                frame.contour.stroke(.white.opacity(0.16), lineWidth: 1)
                    .clipShape(frame.contour)
                    .opacity(frame.shell)
            }
        }
        .shadow(color: .black.opacity(0.42 * frame.player), radius: 12, y: 8)
        .frame(width: geometry.panelWidth, height: geometry.panelHeight, alignment: .top)
    }

    private func mediaAnchors(_ frame: NotchFrame) -> some View {
        let progress = frame.playerLayout
        func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * progress }
        let compactWidth = geometry.size(for: .compact).width
        let wing = (geometry.cameraWidth + compactWidth - 14) / 4 + min(0, frame.size.width - compactWidth) / 2
        let size = mix(18, 56)
        let centerY = mix(geometry.cameraHeight / 2, 45)
        return ZStack(alignment: .top) {
            artwork(size: size)
                .offset(x: mix(-wing, -geometry.playerWidth / 2 + 53), y: centerY - size / 2)
            if let track = model.music {
                Waveform(playing: track.playing, reduceMotion: reduceMotion, tint: media.tint)
                    .scaleEffect(mix(0.8, 1))
                    .offset(x: mix(wing, geometry.playerWidth / 2 - 25 - Waveform.width / 2), y: centerY - 7)
            }
        }
        .modifier(NotchDetail(progress: frame.media, blur: 4.5))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hud(_ alert: NotchAlert, frame: NotchFrame) -> some View {
        let width = frame.size.width
        let height = geometry.cameraHeight + min(6, max(0, frame.size.height - geometry.cameraHeight))
        let railWidth = NotchHUDMetrics.railWidth
            + (NotchHUDMetrics.hoveredRailWidth - NotchHUDMetrics.railWidth) * (height - geometry.cameraHeight) / 6
        let inset = NotchHUDMetrics.wingInset
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if case .headphones(_, let symbol, true, _) = alert {
                    HeadphoneGlyph(symbol: symbol, reduceMotion: reduceMotion)
                } else {
                    Image(systemName: alert.symbol(for: model.output))
                }
                if let label = alert.leadingLabel {
                    Text(label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
            }
            .font(.system(size: NotchHUDMetrics.symbolSize, weight: .semibold))
            .fixedSize()
            .modifier(NotchDetail(progress: frame.hud, blur: 4, x: 8))

            Spacer(minLength: 0)
            alertReadout(alert, railWidth: railWidth)
                .fixedSize()
                .modifier(NotchDetail(progress: frame.hud, blur: 4, x: -8))
        }
        .padding(.horizontal, inset)
        .frame(width: width, height: height)
        .id(alert.kind)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([alert.title, alert.subtitle].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    @ViewBuilder private func alertReadout(_ alert: NotchAlert, railWidth: CGFloat) -> some View {
        if let value = alert.value {
            Meter(value: value, height: NotchHUDMetrics.railHeight, trackOpacity: 0.23, fillOpacity: 1)
                .frame(width: railWidth)
                .animation(reduceMotion ? nil : NotchMotion.level, value: value)
        } else if let label = alert.trailingLabel {
            Text(label).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: label)
        } else if case .headphones(_, _, true, let battery) = alert {
            ZStack {
                if let battery {
                    Circle().strokeBorder(.white.opacity(0.23), lineWidth: 1.5)
                    Circle().trim(from: 0, to: Double(battery) / 100)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 12, height: 12)
            .padding(.trailing, 3)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: battery)
        }
    }

    private func player(row: Double) -> some View {
        VStack(spacing: 11) {
            if let track = model.music {
                HStack(spacing: 13) {
                    Color.clear.frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if !track.artist.isEmpty {
                            Text(track.artist).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                    }
                    .offset(y: max(0, geometry.cameraHeight - 25))
                    Spacer(minLength: 5)
                    Color.clear.frame(width: Waveform.width, height: 14)
                }
                PlaybackScrubber(track: track) { if !sample { media.control(.seek($0)) } }
                transport(track)
            } else {
                HStack(spacing: 13) {
                    Color.clear.frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nothing playing").font(.system(size: 15, weight: .semibold))
                        Text(media.status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                Color.clear.frame(height: 18)
                transport(nil)
            }
            if row > 0 {
                volumeControl
                    .padding(.horizontal, 9)
                    .padding(.top, 6)
                    .modifier(NotchDetail(progress: row, blur: 3, y: -6))
                    .allowsHitTesting(row > 0.8)
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 17)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func transport(_ track: MediaTrack?) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 31, height: 1)
            Spacer(minLength: 0)
            HStack(spacing: 23) {
                IconControl(icon: "backward.fill", label: "Previous", size: 20) {
                    if !sample { media.control(.previous) }
                }
                .disabled(track?.canSkip == false)
                .opacity(track?.canSkip == false ? 0.36 : 1)
                IconControl(icon: track?.playing == true ? "pause.fill" : "play.fill",
                            label: track?.playing == true ? "Pause" : "Play", size: 23) {
                    if !sample { media.control(.toggle) }
                }
                IconControl(icon: "forward.fill", label: "Next", size: 20) {
                    if !sample { media.control(.next) }
                }
                .disabled(track?.canSkip == false)
                .opacity(track?.canSkip == false ? 0.36 : 1)
            }
            .disabled(track == nil)
            .opacity(track == nil ? 0.36 : 1)
            Spacer(minLength: 0)
            IconControl(icon: model.output?.playerIcon ?? "laptopcomputer",
                        label: "Volume for \(model.output?.routeName ?? "current output")", size: 18) {
                model.outputVolumeOpen.toggle()
            }
            .foregroundStyle(.white.opacity(model.outputVolumeOpen ? 1 : 0.55))
        }
        .frame(height: 36)
    }

    @ViewBuilder private var volumeControl: some View {
        if let output = model.output, let level = output.volume {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").frame(width: 15)
                OutputVolumeRail(
                    level: Binding(get: { model.output?.volume ?? level },
                                   set: { if !sample { signals.setVolume($0) } }),
                    label: "Volume for \(output.routeName)"
                )
                Image(systemName: "speaker.wave.3.fill").frame(width: 15)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))
            .frame(height: 25)
        } else {
            Text("Volume unavailable for this output")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .frame(height: 25)
        }
    }

    private func artwork(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.19).fill(.white.opacity(0.09))
            if let image = media.image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: model.music?.fallbackArtwork ?? "music.note")
                    .font(.system(size: size * 0.39, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.19))
        .accessibilityHidden(true)
    }
}

private struct OutputVolumeRail: View {
    @Binding var level: Double
    let label: String

    var body: some View {
        GeometryReader { proxy in
            Meter(value: level, height: 4, trackOpacity: 0.20, fillOpacity: 0.57)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { change in
                        level = min(1, max(0, change.location.x / max(1, proxy.size.width)))
                    })
        }
        .accessibilityRepresentation {
            Slider(value: $level, in: 0...1) { Text(label) }
        }
    }
}

private struct HeadphoneGlyph: View {
    let symbol: String
    let reduceMotion: Bool
    @ViewState private var startedAt = Date.now

    var body: some View {
        if !reduceMotion, symbol == "airpodspro" || symbol == "airpods" {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let angle = context.date.timeIntervalSince(startedAt) * .pi / 1.45
                let spread = cos(angle)
                let stem = symbol == "airpodspro" ? "airpodpro" : "airpod"
                ZStack {
                    bud(stem + ".left", angle: angle, x: -4.5 * spread)
                        .zIndex(sin(angle) > 0 ? 1 : 0)
                    bud(stem + ".right", angle: -angle, x: 4.5 * spread)
                }
                .frame(width: 19, height: 17)
            }
        } else {
            Image(systemName: symbol)
        }
    }

    private func bud(_ name: String, angle: Double, x: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .scaleEffect(x: 0.72 + 0.28 * abs(cos(angle)), y: 1)
            .offset(x: x)
    }
}

private struct IconControl: View {
    let icon: String
    let label: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 31, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct PlaybackScrubber: View {
    let track: MediaTrack
    let seek: (Double) -> Void
    @ViewState private var scrubbing: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = scrubbing ?? track.position(at: context.date)
            HStack(spacing: 8) {
                if track.canSeek {
                    Text(time(position)).frame(width: 36, alignment: .leading)
                    GeometryReader { proxy in
                        Meter(value: position / track.duration, height: 5, fillOpacity: 0.55)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { scrubbing = fraction($0.location.x, width: proxy.size.width) * track.duration }
                                .onEnded {
                                    seek(fraction($0.location.x, width: proxy.size.width) * track.duration)
                                    scrubbing = nil
                                })
                    }
                    .frame(height: 16)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(time(position))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: seek(min(track.duration, position + 5))
                        case .decrement: seek(max(0, position - 5))
                        @unknown default: break
                        }
                    }
                    Text("−" + time(max(0, track.duration - position))).frame(width: 40, alignment: .trailing)
                } else if track.isLive {
                    Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                    Text("LIVE").foregroundStyle(.white.opacity(0.58))
                    Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                }
            }
            .frame(height: 16)
            .font(.system(size: 9.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.57))
        }
        .onChange(of: track.id) { scrubbing = nil }
    }

    private func fraction(_ x: CGFloat, width: CGFloat) -> Double { min(1, max(0, x / max(1, width))) }

    private func time(_ duration: Double) -> String {
        let seconds = Int(duration.rounded(.down))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct Meter: View {
    let value: Double
    var height: CGFloat = 4
    var trackOpacity: Double = 0.18
    var fillOpacity: Double = 0.8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(trackOpacity))
                Capsule().fill(.white.opacity(fillOpacity))
                    .frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: height)
    }
}
