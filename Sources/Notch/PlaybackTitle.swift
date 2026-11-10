import SwiftUI

struct PlaybackTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String

    var body: some View {
        let label = Text(verbatim: title).font(.system(size: 13, weight: .medium)).lineLimit(1)
        if reduceMotion {
            label
        } else {
            ViewThatFits(in: .horizontal) {
                label.fixedSize(horizontal: true, vertical: false)
                ScrollingPlaybackTitle(label: label).id(title)
            }
            .accessibilityRepresentation { Text(verbatim: title) }
        }
    }
}

private struct ScrollingPlaybackTitle<Label: View>: View {
    @ViewState private var textWidth: CGFloat = 0
    @ViewState private var startedAt = Date.now
    let label: Label

    private let gap: CGFloat = 24
    private let pointsPerSecond: CGFloat = 26
    private let pause: TimeInterval = 1.2

    var body: some View {
        label
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                label.fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                        textWidth = width
                        startedAt = .now
                    }
            }
            .overlay {
                GeometryReader { proxy in
                    if textWidth > proxy.size.width, proxy.size.width > 0 {
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            let distance = textWidth + gap
                            let cycle = pause + TimeInterval(distance / pointsPerSecond)
                            let elapsed = max(0, context.date.timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: cycle)
                            let offset = max(0, elapsed - pause) * pointsPerSecond
                            HStack(spacing: gap) {
                                label
                                label
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(x: -offset)
                            .frame(width: proxy.size.width, alignment: .leading)
                            .clipped()
                            .mask {
                                HStack(spacing: 0) {
                                    LinearGradient(colors: [.white.opacity(offset > 0 ? 0 : 1), .white],
                                                   startPoint: .leading, endPoint: .trailing).frame(width: 7)
                                    Color.white
                                    LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 9)
                                }
                            }
                        }
                    } else {
                        label
                    }
                }
            }
    }
}
