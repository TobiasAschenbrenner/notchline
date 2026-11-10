import SwiftUI

#if DEBUG
#Preview("Notch States") {
    NotchGalleryView()
        .frame(width: 515)
        .padding(16)
}
#endif

struct NotchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaMonitor
    @ObservedObject var signals: SystemSignals
    var geometry: NotchGeometry
    var sample = false

    @ViewState private var scene: NotchScene?
    @ViewState private var motion: NotchMotion?
    @ViewState private var pulse: NotchLimitPulse?

    private var outputVolume: Binding<Double>? {
        guard let level = model.output?.volume else { return nil }
        return Binding(
            get: { model.output?.volume ?? level },
            set: { if !sample { signals.setVolume($0) } }
        )
    }

    var body: some View {
        let target = NotchScene(model: model)
        let displayed = scene ?? target
        let resting = NotchFrame(displayed.presentation, geometry: geometry, alert: displayed.alert)
        TimelineView(.animation(paused: motion == nil && pulse == nil)) { _ in
            notch(currentFrame(resting, alert: displayed.alert))
        }
        .onChange(of: target, initial: true) { old, new in
            if old.alert?.kind != new.alert?.kind { pulse = nil }
            if scene != nil, model.isOverlayVisible, old.presentation != new.presentation, !reduceMotion {
                let now = ProcessInfo.processInfo.systemUptime
                var start = motion?.frame(at: now) ?? NotchFrame(old.presentation, geometry: geometry, alert: old.alert)
                if let alert = old.alert, alert.kind == start.alert?.kind { start.alert = alert }
                motion = NotchMotion(from: start, to: new, geometry: geometry, at: now)
            }
            scene = new
        }
        .onChange(of: geometry) { motion = nil }
        .onChange(of: model.isOverlayVisible) { motion = nil; pulse = nil }
        .onChange(of: reduceMotion) { motion = nil; pulse = nil }
        .onChange(of: model.levelLimitAt) { _, timestamp in
            guard let timestamp, model.isOverlayVisible, !reduceMotion else { return }
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
                NotchPlaybackView(
                    track: model.track, status: media.status, output: model.output, outputVolume: outputVolume,
                    cameraHeight: geometry.cameraHeight, volumeRowProgress: frame.volumeRow,
                    isVolumeControlOpen: $model.outputVolumeOpen, sendCommand: sendPlaybackCommand
                )
                    .frame(width: geometry.playerWidth)
                    .modifier(NotchDetail(progress: frame.player, blur: 5, y: -8))
                    .allowsHitTesting(frame.player > 0.8)
            }
            if frame.media > 0 {
                NotchMediaAnchors(frame: frame, geometry: geometry, track: model.track, image: media.image, tint: media.tint)
            }
            if frame.hud > 0, let alert = frame.alert {
                NotchAlertView(alert: alert, frame: frame, cameraHeight: geometry.cameraHeight, output: model.output)
            }
            if frame.peek > 0, let track = model.track {
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

    private func sendPlaybackCommand(_ command: MediaMonitor.Command) {
        if !sample { media.control(command) }
    }
}
