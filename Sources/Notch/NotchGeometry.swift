import SwiftUI

struct NotchGeometry: Equatable {
    var cameraWidth: CGFloat
    var cameraHeight: CGFloat
    static let preview = NotchGeometry(cameraWidth: 168, cameraHeight: 35)

    var compactPlaybackWidth: CGFloat { cameraWidth + 84 }
    var playerWidth: CGFloat { max(362, cameraWidth + 190) }
    var panelWidth: CGFloat { max(playerWidth, NotchHUDMetrics.width(cameraWidth: cameraWidth, hovered: true)) + 32 }
    var panelHeight: CGFloat { 244 }

    func size(for presentation: NotchPresentation) -> CGSize {
        switch presentation {
        case .idle: return CGSize(width: cameraWidth, height: cameraHeight)
        case .compact: return CGSize(width: compactPlaybackWidth, height: cameraHeight)
        case .alert(.headphones, _): return CGSize(width: cameraWidth + 79, height: cameraHeight)
        case .alert(_, let hovered):
            return CGSize(width: NotchHUDMetrics.width(cameraWidth: cameraWidth, hovered: hovered),
                          height: cameraHeight + (hovered ? 6 : 0))
        case .peek: return CGSize(width: compactPlaybackWidth, height: cameraHeight + 24)
        case .expanded: return CGSize(width: playerWidth, height: 180)
        case .volumeControl: return CGSize(width: playerWidth, height: 212)
        }
    }
}
