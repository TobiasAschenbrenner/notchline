import Foundation

enum NotchHUDMetrics {
    // Widths measured in the recording at 2×, with room for the top shoulders.
    static let railWidth: CGFloat = 68
    static let hoveredRailWidth: CGFloat = 79
    static let railHeight: CGFloat = 4
    static let leadingInset: CGFloat = 12.5
    static let trailingInset: CGFloat = 16
    static let headphoneWingInset: CGFloat = 12.5
    static let symbolSize: CGFloat = 13
    static let symbolColumnWidth: CGFloat = 19
    static let shoulder: CGFloat = 5
    static let corner: CGFloat = 11

    static func width(cameraWidth: CGFloat, hovered: Bool = false) -> CGFloat {
        cameraWidth + (hovered ? 223 : 193)
    }
}
