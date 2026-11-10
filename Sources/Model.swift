import SwiftUI

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

@MainActor
final class NotchModel: ObservableObject {
    @Published private(set) var expanded = false
    @Published private(set) var alert: NotchAlert?
    @Published private(set) var levelLimitAt: TimeInterval?
    @Published var outputVolumeOpen = false
    @Published var presentationVisible = true
    @Published private(set) var trackPeek = false
    @Published var power: PowerState?
    @Published var output: SoundOutput?
    @Published var brightness: Double?
    @Published var focus: Bool?
    @Published var focusAccess = ""
    @Published private(set) var music: MediaTrack?
    @Published private(set) var compactMusic = false

    @Published var outline = UserDefaults.standard.object(forKey: "outline") as? Bool ?? false {
        didSet { UserDefaults.standard.set(outline, forKey: "outline") }
    }
    @Published var powerAlerts = UserDefaults.standard.object(forKey: "powerAlerts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(powerAlerts, forKey: "powerAlerts") }
    }
    @Published var levelAlerts = UserDefaults.standard.object(forKey: "levelAlerts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(levelAlerts, forKey: "levelAlerts") }
    }
    @Published var headphonesAlerts = UserDefaults.standard.object(forKey: "headphonesAlerts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(headphonesAlerts, forKey: "headphonesAlerts") }
    }
    @Published var focusAlerts = UserDefaults.standard.object(forKey: "focusAlerts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(focusAlerts, forKey: "focusAlerts") }
    }
    private var expiration: Task<Void, Never>?
    private var peekExpiration: Task<Void, Never>?
    private var idleExpiration: Task<Void, Never>?
    private var preview = false
    private var lastHeadphoneAlert: (name: String, connected: Bool, at: Date)?

    func show(_ alert: NotchAlert, isPreview: Bool = false, pulseLimit: Bool = false) {
        guard isPreview || (!preview && allows(alert)) else { return }
        guard isPreview || !expanded || alert.value != nil else { return }
        let isNewLevel = alert.value != nil && self.alert?.kind != alert.kind
        var hold = alert.duration
        if isNewLevel {
            hold += 0.45
            if compactMusic || expanded || self.alert != nil { hold += NotchMotion.handoffDuration }
        }
        hideTrackPeek()
        expiration?.cancel()
        preview = isPreview
        self.alert = alert
        if pulseLimit { levelLimitAt = ProcessInfo.processInfo.systemUptime }
        expiration = Task { [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            self?.dismissAlert()
        }
    }

    func showHeadphones(_ name: String, icon: String, connected: Bool, battery: Int? = nil, now: Date = .now) {
        guard headphonesAlerts else { return }
        if let lastHeadphoneAlert, lastHeadphoneAlert.name == name,
           lastHeadphoneAlert.connected == connected, now.timeIntervalSince(lastHeadphoneAlert.at) < 2.5 {
            if let battery, connected { updateHeadphoneBattery(name, battery: battery) }
            return
        }
        lastHeadphoneAlert = (name, connected, now)
        show(.headphones(name, icon, connected: connected, battery: battery))
    }

    func updateHeadphoneBattery(_ name: String, battery: Int) {
        guard case .headphones(let currentName, let icon, true, nil) = alert,
              name == currentName, (0...100).contains(battery) else { return }
        alert = .headphones(name, icon, connected: true, battery: battery)
    }

    func dismissAlert() {
        expiration?.cancel()
        if alert != nil { alert = nil }
        preview = false
    }

    func setExpanded(_ expanded: Bool) {
        dismissAlert()
        hideTrackPeek()
        guard expanded != self.expanded else { return }
        self.expanded = expanded
        if !expanded { outputVolumeOpen = false }
    }

    func endLevelHover() {
        guard expanded, alert?.value != nil else { return }
        expanded = false
        outputVolumeOpen = false
    }

    func updateFocus(_ enabled: Bool) {
        guard focus != enabled else { return }
        let wasKnown = focus != nil
        focus = enabled
        if wasKnown || enabled { show(.focus(enabled)) }
    }

    func updateTrack(_ track: MediaTrack?) {
        let previous = music
        if previous != track { music = track }
        guard track?.playing != previous?.playing || track?.id != previous?.id else { return }
        idleExpiration?.cancel()
        guard let track else {
            hideTrackPeek()
            compactMusic = false
            return
        }
        if track.playing {
            compactMusic = true
            if previous?.id != track.id && !expanded && alert == nil { showTrackPeek() }
        } else if compactMusic {
            hideTrackPeek()
            idleExpiration = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.compactMusic = false
            }
        }
    }

    func showTrackPeek() {
        guard compactMusic, !expanded, alert == nil else { return }
        peekExpiration?.cancel()
        trackPeek = true
        peekExpiration = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hideTrackPeek()
        }
    }

    private func hideTrackPeek() {
        peekExpiration?.cancel()
        if trackPeek { trackPeek = false }
    }

    private func allows(_ alert: NotchAlert) -> Bool {
        switch alert {
        case .volume, .brightness: return levelAlerts
        case .headphones: return headphonesAlerts
        case .focus: return focusAlerts
        case .power: return powerAlerts
        }
    }
}
