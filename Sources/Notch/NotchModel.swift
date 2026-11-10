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

    @Published var outline: Bool {
        didSet { defaults.set(outline, forKey: "outline") }
    }
    @Published var powerAlerts: Bool {
        didSet { defaults.set(powerAlerts, forKey: "powerAlerts") }
    }
    @Published var volumeAlerts: Bool {
        didSet { defaults.set(volumeAlerts, forKey: "volumeAlerts") }
    }
    @Published var brightnessAlerts: Bool {
        didSet { defaults.set(brightnessAlerts, forKey: "brightnessAlerts") }
    }
    @Published var headphonesAlerts: Bool {
        didSet { defaults.set(headphonesAlerts, forKey: "headphonesAlerts") }
    }
    @Published var focusAlerts: Bool {
        didSet { defaults.set(focusAlerts, forKey: "focusAlerts") }
    }
    private let defaults: UserDefaults
    private var alertExpirationTask: Task<Void, Never>?
    private var trackPeekExpirationTask: Task<Void, Never>?
    private var compactPlaybackExpirationTask: Task<Void, Never>?
    private var isPreviewAlert = false
    private var lastHeadphoneAlert: (name: String, connected: Bool, at: Date)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let previousLevelAlerts = defaults.object(forKey: "levelAlerts") as? Bool ?? true
        outline = defaults.object(forKey: "outline") as? Bool ?? false
        powerAlerts = defaults.object(forKey: "powerAlerts") as? Bool ?? true
        volumeAlerts = defaults.object(forKey: "volumeAlerts") as? Bool ?? previousLevelAlerts
        brightnessAlerts = defaults.object(forKey: "brightnessAlerts") as? Bool ?? previousLevelAlerts
        headphonesAlerts = defaults.object(forKey: "headphonesAlerts") as? Bool ?? true
        focusAlerts = defaults.object(forKey: "focusAlerts") as? Bool ?? true
    }

    func show(_ alert: NotchAlert, isPreview: Bool = false, pulseLimit: Bool = false) {
        guard isPreview || (!isPreviewAlert && isAlertEnabled(alert.kind)) else { return }
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

    func isAlertEnabled(_ kind: NotchAlert.Kind) -> Bool {
        switch kind {
        case .volume: return volumeAlerts
        case .brightness: return brightnessAlerts
        case .headphones: return headphonesAlerts
        case .focus: return focusAlerts
        case .power: return powerAlerts
        }
    }
}
