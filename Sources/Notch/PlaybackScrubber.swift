import SwiftUI

struct PlaybackScrubber: View {
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
                        LevelMeter(value: position / track.duration, height: 6, fillOpacity: 0.52)
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
