import Foundation

enum NotchAlert: Equatable {
    enum Kind: Hashable { case volume, brightness, headphones, focus, power }

    case volume(Double, muted: Bool)
    case brightness(Double)
    case headphones(String, String, connected: Bool, battery: Int? = nil)
    case focus(Bool)
    case power(PowerState, title: String)

    var kind: Kind {
        switch self {
        case .volume: return .volume
        case .brightness: return .brightness
        case .headphones: return .headphones
        case .focus: return .focus
        case .power: return .power
        }
    }

    var title: String {
        switch self {
        case .volume: return "Sound"
        case .brightness: return "Display"
        case .headphones(let name, _, _, _): return name
        case .focus(let on): return on ? "Focus on" : "Focus off"
        case .power(_, let title): return title
        }
    }

    var subtitle: String {
        switch self {
        case .volume(let value, let muted): return muted || value == 0 ? "Muted" : ""
        case .brightness: return ""
        case .headphones(_, _, let connected, let battery):
            if let battery, connected { return "Connected, \(battery)% battery" }
            return connected ? "Connected" : "Disconnected"
        case .focus(let on): return on ? "Notifications silenced" : "Notifications resumed"
        case .power(let power, _): return "\(power.percentage)% remaining"
        }
    }

    var leadingLabel: String? { value == nil ? nil : title }

    var trailingLabel: String? {
        switch self {
        case .focus(let enabled): return enabled ? "On" : "Off"
        case .power(let power, _): return "\(power.percentage)%"
        default: return nil
        }
    }

    var icon: String {
        switch self {
        case .volume(let value, let muted):
            if muted || value == 0 { return "speaker.slash.fill" }
            return value < 0.34 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .headphones(_, let icon, _, _): return icon
        case .focus: return "moon.fill"
        case .power(let power, _): return power.icon
        }
    }

    func symbol(for output: SoundOutput?) -> String {
        if case .volume = self,
           let output, output.isPersonalAudio {
            return output.icon
        }
        return icon
    }

    var value: Double? {
        switch self {
        case .volume(let value, let muted): return muted ? 0 : value
        case .brightness(let value): return value
        default: return nil
        }
    }

    var duration: TimeInterval {
        if case .headphones = self { return 6 }
        return value == nil ? 3 : 1.65
    }
}
