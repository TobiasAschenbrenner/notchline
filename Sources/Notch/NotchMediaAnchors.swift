import AppKit
import SwiftUI

struct NotchMediaAnchors: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let frame: NotchFrame
    let geometry: NotchGeometry
    let track: MediaTrack?
    let image: NSImage?
    let tint: Color

    var body: some View {
        let progress = frame.playerLayout
        func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * progress }
        let compactWidth = geometry.size(for: .compact).width
        let wing = (geometry.cameraWidth + compactWidth - 14) / 4 + min(0, frame.size.width - compactWidth) / 2
        let size = mix(18, 56)
        let centerY = mix(geometry.cameraHeight / 2, 45)
        return ZStack(alignment: .top) {
            artwork(size: size)
                .offset(x: mix(-wing, -geometry.playerWidth / 2 + 53), y: centerY - size / 2)
            if let track {
                PlaybackWaveform(playing: track.playing, reduceMotion: reduceMotion, tint: tint)
                    .scaleEffect(mix(0.8, 1))
                    .offset(x: mix(wing, geometry.playerWidth / 2 - 25 - PlaybackWaveform.width / 2), y: centerY - 7)
            }
        }
        .modifier(NotchDetail(progress: frame.media, blur: 4.5))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func artwork(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.19).fill(.white.opacity(0.09))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: track?.fallbackArtwork ?? "music.note")
                    .font(.system(size: size * 0.39, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.19))
        .accessibilityHidden(true)
    }
}

struct PlaybackWaveform: View {
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
