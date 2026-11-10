import SwiftUI

struct NotchScene: Equatable {
    let presentation: NotchPresentation
    let alert: NotchAlert?

    @MainActor
    init(model: NotchModel) {
        presentation = NotchPresentation(model: model)
        alert = model.alert
    }
}

struct NotchFrame {
    var size: CGSize
    var contour: NotchContour
    var alert: NotchAlert?
    var shell: Double = 1
    var player: Double = 0
    var volumeRow: Double = 0
    var playerLayout: Double = 0
    var media: Double = 0
    var hud: Double = 0
    var peek: Double = 0

    init(_ presentation: NotchPresentation, geometry: NotchGeometry, alert: NotchAlert? = nil) {
        size = geometry.size(for: presentation)
        contour = presentation.contour
        self.alert = alert
        shell = presentation == .idle ? 0 : 1
        player = presentation.isPlayer ? 1 : 0
        volumeRow = presentation == .volumeControl ? 1 : 0
        playerLayout = player
        media = presentation.isPlayer || presentation == .compact || presentation == .peek ? 1 : 0
        hud = presentation.alertKind == nil ? 0 : 1
        peek = presentation == .peek ? 1 : 0
    }
}

struct NotchMotion {
    static let level = Animation.timingCurve(0.22, 0.20, 0.30, 1, duration: 0.15)
    static let handoffDuration = 0.33

    let startedAt: TimeInterval
    private let legs: [Leg]

    init(from start: NotchFrame, to scene: NotchScene, geometry: NotchGeometry, at time: TimeInterval) {
        startedAt = time
        let end = NotchFrame(scene.presentation, geometry: geometry, alert: scene.alert)
        let idle = geometry.size(for: .idle)
        if start.alert?.kind != end.alert?.kind, start.alert != nil || end.alert != nil,
           start.size.width > idle.width + 12, end.size.width > idle.width + 12 {
            var neck = NotchFrame(.idle, geometry: geometry)
            neck.size.width += start.playerLayout > 0.5 ? 25 : 8
            neck.size.height += start.playerLayout > 0.5 ? 14 : 0
            neck.shell = 1
            legs = [Leg(from: start, to: neck, curve: .handoff),
                    Leg(from: neck, to: end, curve: Self.curve(from: neck, to: end))]
        } else {
            legs = [Leg(from: start, to: end, curve: Self.curve(from: start, to: end))]
        }
    }

    var endsAt: TimeInterval { startedAt + legs.reduce(0) { $0 + $1.curve.duration } }

    func frame(at time: TimeInterval) -> NotchFrame {
        var elapsed = max(0, time - startedAt)
        for leg in legs {
            if elapsed < leg.curve.duration { return leg.frame(at: elapsed) }
            elapsed -= leg.curve.duration
        }
        return legs[legs.count - 1].to
    }

    private static func curve(from: NotchFrame, to: NotchFrame) -> Curve {
        if from.player == 1, to.player == 1, from.volumeRow != to.volumeRow { return .volumeRow }
        if to.player == 1, from.playerLayout < 1 { return .playerOpen }
        if from.playerLayout > to.playerLayout { return .playerClose }
        if to.hud == 1, from.alert?.kind != to.alert?.kind { return .hudOpen }
        if from.hud > 0, to.hud == 1 { return .hudResize }
        return .compact
    }

    private enum Curve {
        case playerOpen, playerClose, volumeRow, hudOpen, hudResize, handoff, compact

        var duration: Double {
            switch self {
            case .playerOpen: return 0.60
            case .playerClose: return 0.52
            case .volumeRow: return 0.18
            case .hudOpen, .compact: return 0.55
            case .hudResize: return 0.27
            case .handoff: return NotchMotion.handoffDuration
            }
        }

        func shape(at time: Double) -> Double {
            if self == .playerOpen {
                // The opening spring peaks at about 260 ms with 9% overshoot.
                return 1 - exp(-9.3 * time) * (cos(12.1 * time) + (9.3 / 12.1) * sin(12.1 * time))
            }
            let rate: Double
            switch self {
            case .playerClose: rate = 16
            case .hudOpen, .compact: rate = 19
            case .handoff: rate = 15
            case .hudResize: rate = 26
            case .volumeRow: rate = 30
            case .playerOpen: return 1
            }
            func approach(_ t: Double) -> Double { 1 - (1 + rate * t) * exp(-rate * t) }
            return approach(time) / approach(duration)
        }
    }

    private struct Leg {
        let from: NotchFrame
        let to: NotchFrame
        let curve: Curve

        func frame(at time: Double) -> NotchFrame {
            let progress = curve.shape(at: time)
            func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
            func ramp(_ start: Double, _ end: Double) -> Double {
                let t = min(1, max(0, (time - start) / (end - start)))
                return t * t * (3 - 2 * t)
            }
            func detail(_ a: Double, _ b: Double, enter: (Double, Double), exit: Double) -> Double {
                let finish = min(enter.1, curve.duration)
                let begin = min(enter.0, finish * 0.8)
                return mix(a, b, b > a ? ramp(begin, finish) : ramp(0, exit))
            }

            var result = from
            // Preserve the spring across the width while softening the bounce down the screen.
            let heightProgress = curve == .playerOpen && progress > 1 ? 1 + (progress - 1) * 0.35 : progress
            result.size = CGSize(width: mix(from.size.width, to.size.width, progress),
                                 height: mix(from.size.height, to.size.height, heightProgress))
            result.contour = NotchContour(shoulder: mix(from.contour.shoulder, to.contour.shoulder, progress),
                                          corner: mix(from.contour.corner, to.contour.corner, progress))
            result.alert = to.alert ?? from.alert
            result.shell = to.shell > from.shell
                ? mix(from.shell, to.shell, ramp(0, 0.065))
                : mix(from.shell, to.shell, ramp(curve.duration * 0.52, curve.duration))
            result.playerLayout = mix(from.playerLayout, to.playerLayout, progress)
            result.player = detail(from.player, to.player, enter: (0.045, 0.20), exit: 0.14)
            result.volumeRow = detail(from.volumeRow, to.volumeRow, enter: (0.025, 0.13), exit: 0.11)
            result.hud = detail(from.hud, to.hud, enter: (0.12, 0.35), exit: 0.10)
            result.peek = detail(from.peek, to.peek, enter: (0.085, 0.27), exit: 0.12)
            let compactAfterPlayer = curve == .playerClose
            result.media = detail(from.media, to.media, enter: to.player == 1 ? (0.045, 0.20) : (0.17, 0.41),
                                  exit: curve == .handoff ? 0.14 : 0.18)
            if from.media == 1, to.media == 1, from.playerLayout != to.playerLayout {
                let clears = ramp(0, 0.083)
                let sharpens = compactAfterPlayer ? ramp(0.13, 0.29) : ramp(0.068, 0.20)
                result.media = 1 - 0.76 * clears * (1 - sharpens)
            }
            return result
        }
    }
}

struct NotchLimitPulse {
    static let duration = 0.28
    let startedAt: TimeInterval
    var initialWidth: CGFloat = 0

    func width(at time: TimeInterval) -> CGFloat {
        let progress = min(1, max(0, (time - startedAt) / Self.duration))
        return initialWidth * (1 - progress) + 1.65 * pow(sin(progress * .pi), 2)
    }
}

struct NotchDetail: ViewModifier {
    let progress: Double
    var blur: CGFloat = 4
    var x: CGFloat = 0
    var y: CGFloat = 0

    func body(content: Content) -> some View {
        let remaining = 1 - progress
        content
            .offset(x: x * remaining, y: y * remaining)
            .blur(radius: blur * remaining)
            .opacity(progress)
    }
}
