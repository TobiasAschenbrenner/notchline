import SwiftUI

struct LevelMeter: View {
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
