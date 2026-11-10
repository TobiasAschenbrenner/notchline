import AppKit
import SwiftUI

enum PlaybackHeaderLayout {
    static let artworkWidth: CGFloat = 56
    static let artworkInset: CGFloat = 33
    static let waveformInset: CGFloat = 40
    static let topInset: CGFloat = 18
    static let centerY = topInset + artworkWidth / 2
}

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
        let compactWidth = geometry.compactPlaybackWidth
        let compactBodyWidth = compactWidth - 2 * NotchPresentation.compact.contour.shoulder
        let wing = (geometry.cameraWidth + compactBodyWidth) / 4 + min(0, frame.size.width - compactWidth) / 2
        let width = mix(20, PlaybackHeaderLayout.artworkWidth)
        let height = width / artworkAspectRatio
        let centerY = mix(geometry.cameraHeight / 2, PlaybackHeaderLayout.centerY)
        let artworkX = -geometry.playerWidth / 2 + PlaybackHeaderLayout.artworkInset + PlaybackHeaderLayout.artworkWidth / 2
        let waveformX = geometry.playerWidth / 2 - PlaybackHeaderLayout.waveformInset - PlaybackWaveform.width / 2
        return ZStack(alignment: .top) {
            artwork(width: width, height: height)
                .offset(x: mix(-wing, artworkX), y: centerY - height / 2)
            if let track {
                PlaybackWaveform(playing: track.playing, reduceMotion: reduceMotion, tint: tint)
                    .scaleEffect(mix(0.76, 1))
                    .offset(x: mix(wing, waveformX), y: centerY - 7)
            }
        }
        .modifier(NotchDetail(progress: frame.media, blur: 4.5))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var artworkAspectRatio: CGFloat {
        guard let image, image.size.height > 0 else { return track?.isFromBrowser == true ? 16.0 / 9 : 1 }
        return min(2, max(1, image.size.width / image.size.height))
    }

    private func artwork(width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.18)
        return ZStack {
            shape.fill(.white.opacity(0.09))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: track?.fallbackArtwork ?? "music.note")
                    .font(.system(size: height * 0.39, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

struct PlaybackWaveform: View {
    static let width: CGFloat = 21
    var playing: Bool
    var reduceMotion: Bool
    var tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18, paused: !playing || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.75) {
                ForEach(0..<5) { index in
                    Capsule().fill(tint.opacity(0.85))
                        .frame(width: 2, height: playing && !reduceMotion
                               ? 3 + abs(sin(time * 5 + Double(index) * 1.21)) * 9
                               : CGFloat([4, 7, 11, 7, 4][index]))
                }
            }
            .frame(width: Self.width, height: 14)
        }
        .accessibilityHidden(true)
    }
}
