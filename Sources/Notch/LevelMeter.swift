import SwiftUI

struct LevelMeter: View {
    let value: Double
    var height: CGFloat = 4
    var trackOpacity: Double = 0.18
    var fillOpacity: Double = 0.8
    var roundsFill = true

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(trackOpacity))
                RoundedRectangle(cornerRadius: roundsFill ? height / 2 : 0, style: .circular)
                    .fill(.white.opacity(fillOpacity))
                    .frame(width: proxy.size.width * min(1, max(0, value)))
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}
