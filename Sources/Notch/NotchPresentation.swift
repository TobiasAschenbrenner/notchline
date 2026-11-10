import SwiftUI

enum NotchPresentation: Equatable {
    case idle, compact, peek, expanded, volumeControl
    case alert(NotchAlert.Kind, hovered: Bool = false)

    var isPlayer: Bool { self == .expanded || self == .volumeControl }

    var alertKind: NotchAlert.Kind? {
        if case .alert(let kind, _) = self { return kind }
        return nil
    }

    var contour: NotchContour {
        switch self {
        case .idle: return .init(shoulder: 2, corner: 9)
        case .compact, .alert(.headphones, _): return .init(shoulder: 5, corner: 11)
        case .alert: return .init(shoulder: NotchHUDMetrics.shoulder, corner: NotchHUDMetrics.corner)
        case .peek: return .init(shoulder: 5, corner: 14)
        case .expanded, .volumeControl: return .init(shoulder: 15, corner: 38)
        }
    }

    @MainActor
    init(model: NotchModel) {
        if let alert = model.alert { self = .alert(alert.kind, hovered: model.isExpanded && alert.value != nil) }
        else if model.isExpanded { self = model.outputVolumeOpen ? .volumeControl : .expanded }
        else if model.showsTrackPeek { self = .peek }
        else if model.showsCompactPlayback { self = .compact }
        else { self = .idle }
    }
}
