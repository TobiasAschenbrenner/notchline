import SwiftUI

struct NotchAlertView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let alert: NotchAlert
    let frame: NotchFrame
    let cameraHeight: CGFloat
    let output: SoundOutput?

    var body: some View {
        let width = frame.size.width
        let height = cameraHeight + min(6, max(0, frame.size.height - cameraHeight))
        let railWidth = NotchHUDMetrics.railWidth
            + (NotchHUDMetrics.hoveredRailWidth - NotchHUDMetrics.railWidth) * (height - cameraHeight) / 6
        let inset = NotchHUDMetrics.wingInset
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if case .headphones(_, let symbol, true, _) = alert {
                    HeadphoneGlyph(symbol: symbol, reduceMotion: reduceMotion)
                } else {
                    Image(systemName: alert.symbol(for: output))
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
            LevelMeter(value: value, height: NotchHUDMetrics.railHeight, trackOpacity: 0.23, fillOpacity: 1)
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
