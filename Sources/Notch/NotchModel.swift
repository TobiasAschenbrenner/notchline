import Combine
import Foundation

@MainActor
final class NotchModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var alert: NotchAlert?
    @Published private(set) var levelLimitAt: TimeInterval?
    @Published var outputVolumeOpen = false
    @Published var isOverlayVisible = true
    @Published private(set) var showsTrackPeek = false
    @Published var power: PowerState?
    @Published var output: SoundOutput?
    @Published var brightness: Double?
    @Published var focus: Bool?
    @Published var focusAccess = ""
    @Published private(set) var track: MediaTrack?
    @Published private(set) var showsCompactPlayback = false

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
    private var alertExpirationTask: Task<Void, Never>?
    private var trackPeekExpirationTask: Task<Void, Never>?
    private var compactPlaybackExpirationTask: Task<Void, Never>?
    private var isPreviewAlert = false
    private var lastHeadphoneAlert: (name: String, connected: Bool, at: Date)?

    func show(_ alert: NotchAlert, isPreview: Bool = false, pulseLimit: Bool = false) {
        guard isPreview || (!isPreviewAlert && allows(alert)) else { return }
        guard isPreview || !isExpanded || alert.value != nil else { return }
        let isNewLevel = alert.value != nil && self.alert?.kind != alert.kind
        var hold = alert.duration
        if isNewLevel {
            hold += 0.45
            if showsCompactPlayback || isExpanded || self.alert != nil { hold += NotchMotion.handoffDuration }
        }
        hideTrackPeek()
        alertExpirationTask?.cancel()
        isPreviewAlert = isPreview
        self.alert = alert
        if pulseLimit { levelLimitAt = ProcessInfo.processInfo.systemUptime }
        alertExpirationTask = Task { [weak self] in
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
        alertExpirationTask?.cancel()
        if alert != nil { alert = nil }
        isPreviewAlert = false
    }

    func setExpanded(_ expanded: Bool) {
        dismissAlert()
        hideTrackPeek()
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if !expanded { outputVolumeOpen = false }
    }

    func endLevelHover() {
        guard isExpanded, alert?.value != nil else { return }
        isExpanded = false
        outputVolumeOpen = false
    }

    func updateFocus(_ enabled: Bool) {
        guard focus != enabled else { return }
        let wasKnown = focus != nil
        focus = enabled
        if wasKnown || enabled { show(.focus(enabled)) }
    }

    func updateTrack(_ track: MediaTrack?) {
        let previous = self.track
        if previous != track { self.track = track }
        guard track?.playing != previous?.playing || track?.id != previous?.id else { return }
        compactPlaybackExpirationTask?.cancel()
        guard let track else {
            hideTrackPeek()
            showsCompactPlayback = false
            return
        }
        if track.playing {
            showsCompactPlayback = true
            if previous?.id != track.id && !isExpanded && alert == nil { showTrackPeek() }
        } else if showsCompactPlayback {
            hideTrackPeek()
            compactPlaybackExpirationTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.showsCompactPlayback = false
            }
        }
    }

    private func showTrackPeek() {
        guard showsCompactPlayback, !isExpanded, alert == nil else { return }
        trackPeekExpirationTask?.cancel()
        showsTrackPeek = true
        trackPeekExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hideTrackPeek()
        }
    }

    private func hideTrackPeek() {
        trackPeekExpirationTask?.cancel()
        if showsTrackPeek { showsTrackPeek = false }
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
