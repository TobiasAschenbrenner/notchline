import Foundation

enum NotchHUDMetrics {
    // Widths measured in the recording at 2×, with room for the top shoulders.
    static let railWidth: CGFloat = 68
    static let hoveredRailWidth: CGFloat = 79
    static let railHeight: CGFloat = 4
    static let wingInset: CGFloat = 15
    static let symbolSize: CGFloat = 15
    static let shoulder: CGFloat = 7
    static let corner: CGFloat = 11

    static func width(cameraWidth: CGFloat, hovered: Bool = false) -> CGFloat {
        cameraWidth + (hovered ? 219 : 189)
    }
}
