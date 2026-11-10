import AppKit
import SwiftUI

@main
struct NotchlineApp {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-test") {
            exit(Diagnostics.run() ? 0 : 1)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = NotchModel()
    private lazy var media = MediaMonitor(model: model)
    private lazy var signals = SystemSignals(model: model)
    private lazy var notch = NotchPanelController(model: model, media: media, signals: signals)

    private var statusItem: NSStatusItem?
    private var visibilityItem: NSMenuItem?
    private var settings: NSWindow?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        configureApplicationMenu()
        notch.start()
        signals.canShowLevelHUD = { [weak self] in self?.notch.canShowLevelHUD ?? false }
        signals.start()
        media.start()

        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.notch.reposition()
            self?.signals.updateDisplay()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.notch.updateSpace() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.notch.updateSpace() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.notch.setLocked(false)
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.notch.setLocked(true) }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.notch.setLocked(true)
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.notch.setLocked(false)
        }

        if !UserDefaults.standard.bool(forKey: "didOpenV1") {
            UserDefaults.standard.set(true, forKey: "didOpenV1")
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        notch.stop()
        signals.stop()
        media.stop()
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        observers.append((center, token))
    }

    private func configureApplicationMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let quit = NSMenuItem(title: "Quit Notchline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func configureMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule", accessibilityDescription: "Notchline")
        let menu = NSMenu()
        let visibility = NSMenuItem(title: "Hide Notch", action: #selector(toggleVisibility(_:)), keyEquivalent: "")
        let preferences = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quit Notchline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for entry in [visibility, preferences] { entry.target = self }
        quit.target = NSApp
        for entry in [visibility, .separator(), preferences, .separator(), quit] { menu.addItem(entry) }
        item.menu = menu
        statusItem = item
        visibilityItem = visibility
    }

    @objc private func toggleVisibility(_ item: NSMenuItem) {
        setNotchVisible(!notch.visible)
    }

    private func setNotchVisible(_ visible: Bool) {
        notch.setVisible(visible)
        visibilityItem?.title = visible ? "Hide Notch" : "Show Notch"
    }

    @objc private func showSettings() {
        if settings == nil {
            let content = SettingsView(model: model, media: media, signals: signals, showOnDesktop: { [weak self] in
                self?.setNotchVisible(true)
                self?.settings?.orderOut(nil)
            }, quit: { NSApp.terminate(nil) })
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "Notchline Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settings = window
        }
        NSApp.activate()
        settings?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private enum Diagnostics {
    static func run() -> Bool {
        let model = NotchModel()
        let geometry = NotchGeometry.preview
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let frame = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.example.player","title":"Example","artist":"Artist","playing":true,"durationMicros":100000000,"elapsedTimeMicros":40000000,"timestampEpochMicros":1700000000000000,"playbackRate":1}}"#
        let track = MediaMonitor.decode(Data(frame.utf8), now: now)?.track
        let liveFrame = #"{"type":"data","diff":false,"payload":{"parentApplicationBundleIdentifier":"com.google.Chrome","title":"Live stream","playing":true,"durationMicros":120000000,"isLiveStream":true}}"#
        let browserFrame = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.google.Chrome","title":"Video","durationMicros":635000000,"prohibitsSkip":true}}"#
        let unknownFrame = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","title":"Loading"}}"#
        let liveTrack = MediaMonitor.decode(Data(liveFrame.utf8), now: now)?.track
        let browserTrack = MediaMonitor.decode(Data(browserFrame.utf8), now: now)?.track
        let unknownTrack = MediaMonitor.decode(Data(unknownFrame.utf8), now: now)?.track
        let cleared = MediaMonitor.decode(Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8), now: now)
        let compact: [NotchPresentation] = [.idle, .compact, .alert(.volume), .alert(.brightness), .alert(.headphones)]
        let low = PowerState(percentage: 10, pluggedIn: false, lowPower: false)
        let prior = PowerState(percentage: 11, pluggedIn: false, lowPower: false)

        model.updateTrack(track)
        let showsPeek = NotchPresentation(model: model) == .peek
        model.show(.volume(0.8, muted: true), isPreview: true)
        let initialAlert = model.alert
        model.show(.focus(true))
        let preservesPreview = model.alert == initialAlert && NotchPresentation(model: model) == .alert(.volume)
        model.setExpanded(true)
        model.outputVolumeOpen = true
        let showsVolume = NotchPresentation(model: model) == .volumeControl
        model.setExpanded(false)

        var hover = NotchHover()
        let waitsToOpen = hover.expansion(inside: true, expanded: false, dragging: false, now: 1) == nil
        let opens = hover.expansion(inside: true, expanded: false, dragging: false, now: 1.10) == true
        let keepsOpen = hover.expansion(inside: false, expanded: true, dragging: true, now: 2) == nil
        let waitsToClose = hover.expansion(inside: false, expanded: true, dragging: false, now: 3) == nil
        let closes = hover.expansion(inside: false, expanded: true, dragging: false, now: 3.15) == false
        let report = #"{"SPBluetoothDataType":[{"device_connected":[{"Earbuds":{"device_address":"11:22:33:44:55:66","device_batteryLevelLeft":"82%","device_batteryLevelRight":"65%","device_batteryLevelCase":"12%"}},{"Other":{"device_batteryLevelMain":"2%"}}]}]}"#
        let battery = AccessoryBattery.charge(in: Data(report.utf8), name: "Earbuds", address: "11-22-33-44-55-66")
        let absentBattery = AccessoryBattery.charge(in: Data(report.utf8), name: "Unknown", address: nil)
        model.show(.headphones("Earbuds", "airpodspro", connected: true), isPreview: true)
        let headphonePreview = model.alert
        model.dismissAlert()
        let batteryModel = NotchModel()
        if batteryModel.headphonesAlerts {
            batteryModel.showHeadphones("Earbuds", icon: "airpodspro", connected: true)
            batteryModel.updateHeadphoneBattery("Earbuds", battery: 65)
        }
        let updatesCharge = !batteryModel.headphonesAlerts || batteryModel.alert?.subtitle == "Connected, 65% battery"
        batteryModel.dismissAlert()

        let alerts: [NotchAlert] = [.volume(0.6, muted: false), .brightness(0.7), .focus(true),
                                    .headphones("Earbuds", "airpodspro", connected: true, battery: 65),
                                    .power(low, title: "Low battery")]
        let standardHUD = geometry.size(for: .alert(.volume))
        let matchesAlertGeometry = alerts.allSatisfy { alert in
            model.show(alert, isPreview: true)
            let presentation = NotchPresentation(model: model)
            let expected = alert.kind == .headphones ? geometry.size(for: .compact) : standardHUD
            return presentation == .alert(alert.kind) && geometry.size(for: presentation) == expected
        }

        let motionModel = NotchModel()
        motionModel.updateTrack(track)
        motionModel.setExpanded(true)
        let compactFrame = NotchFrame(.compact, geometry: geometry)
        let playerMotion = NotchMotion(from: compactFrame, to: NotchScene(model: motionModel), geometry: geometry, at: 0)
        let playerSize = geometry.size(for: .expanded)
        let playerPeak = playerMotion.frame(at: 0.26)
        motionModel.show(.volume(0.5, muted: false), isPreview: true)
        let hoveredHUD = NotchPresentation(model: motionModel)
        let playerToHUD = NotchMotion(from: playerPeak, to: NotchScene(model: motionModel), geometry: geometry, at: 1)
        let playerHUDHandoff = playerToHUD.frame(at: 1 + NotchMotion.handoffDuration)
        motionModel.endLevelHover()
        let keepsLevelOnExit = NotchPresentation(model: motionModel) == .alert(.volume)
        motionModel.show(.volume(0.7, muted: false), isPreview: true)
        let stillSameHUD = NotchPresentation(model: motionModel) == .alert(.volume) && motionModel.alert?.value == 0.7
        let startHUD = NotchFrame(.alert(.volume), geometry: geometry, alert: motionModel.alert)
        motionModel.dismissAlert()
        let returnMotion = NotchMotion(from: startHUD, to: NotchScene(model: motionModel), geometry: geometry, at: 2)
        let handoff = returnMotion.frame(at: 2 + NotchMotion.handoffDuration)
        let retarget = NotchMotion(from: handoff, to: NotchScene(model: motionModel), geometry: geometry, at: 3)
        model.dismissAlert()
        let airPods = SoundOutput(id: 1, source: nil, name: "AirPods Pro", transport: nil, volume: 0.6, muted: false)

        let checks: [(String, Bool)] = [
            ("Compact states align with the menu bar", compact.allSatisfy { geometry.size(for: $0).height == geometry.cameraHeight }),
            ("Track peek and intentional expansion", showsPeek && showsVolume && !model.outputVolumeOpen && geometry.size(for: .volumeControl).height < geometry.panelHeight),
            ("Monochrome HUD mute state", initialAlert?.value == 0 && initialAlert?.icon == "speaker.slash.fill" && initialAlert?.duration == 1.65),
            ("Preview isolation", preservesPreview && model.alert == nil && headphonePreview?.icon == "airpodspro"),
            ("Hover dwell, exit and drag hold", waitsToOpen && opens && keepsOpen && waitsToClose && closes),
            ("AirPods bud charge, case exclusion and late update", battery == 65 && absentBattery == nil && updatesCharge),
            ("Standard HUD and AirPods compact geometry", matchesAlertGeometry && standardHUD.width < geometry.panelWidth),
            ("White HUD rail, device icon and volume bounds", NotchHUDMetrics.railWidth == 68 && NotchHUDMetrics.railHeight == 4
                && alerts[0].symbol(for: airPods) == "airpodspro"
                && initialAlert?.symbol(for: airPods) == "airpodspro"
                && geometry.size(for: .volumeControl).height - playerSize.height == 32),
            ("Player content reveals during expansion and geometry overshoots",
                playerMotion.frame(at: 0.04).player == 0 && playerMotion.frame(at: 0.16).player > 0.7
                && playerPeak.size.width > playerSize.width && playerPeak.size.height > playerSize.height
                && playerMotion.frame(at: 0.6).size == playerSize),
            ("Hover-held level alert survives pointer exit and repeat inputs",
                hoveredHUD == .alert(.volume, hovered: true) && keepsLevelOnExit && stillSameHUD
                && playerHUDHandoff.player < 0.01 && playerHUDHandoff.hud == 0),
            ("HUD retracts before playback and interruption preserves geometry",
                handoff.size.width < compactFrame.size.width && handoff.hud < 0.01 && handoff.media == 0
                && retarget.frame(at: 3).size == handoff.size && returnMotion.frame(at: 3).size == compactFrame.size),
            ("Sound, Display and Focus labels", alerts[0].leadingLabel == "Sound" && alerts[1].leadingLabel == "Display"
                && alerts[2].trailingLabel == "On" && NotchAlert.focus(false).trailingLabel == "Off"),
            ("Hardware level step bounds and fine adjustments", LevelKey.soundUp.nextLevel(from: 0.5, fine: false) == 0.5625
                && LevelKey.displayDown.nextLevel(from: 0.5, fine: true) == 0.484375
                && LevelKey.displayUp.nextLevel(from: 1, fine: false) == 1
                && LevelKey.soundDown.nextLevel(from: 0, fine: false) == 0),
            ("Keyboard filter owns complete presses and passes unsupported keys to macOS", levelKeyRouting()),
            ("System media frame and elapsed position", track?.title == "Example" && track?.position(at: now.addingTimeInterval(20)) == 60),
            ("Live, timed video and unavailable timelines", liveTrack?.isLive == true && liveTrack?.canSeek == false && liveTrack?.canSkip == false
                && browserTrack?.canSeek == true && browserTrack?.canSkip == false && browserTrack?.fallbackArtwork == "play.rectangle.fill"
                && unknownTrack?.isLive == false && unknownTrack?.canSeek == false),
            ("Empty system media session", cleared != nil && cleared?.track == nil),
            ("Battery threshold crosses once", low.crossedWarning(from: prior) && !low.crossedWarning(from: low))
        ]
        for (name, passed) in checks { print("\(passed ? "PASS" : "FAIL")  \(name)") }
        return checks.allSatisfy { $0.1 }
    }

    private static func levelKeyRouting() -> Bool {
        let tap = LevelKeyTap()
        var adjusted: [LevelKey] = []
        var fineStep = false
        func send(_ key: LevelKey, state: Int = 0xA, repeatKey: Bool = false, flags: CGEventFlags = []) -> Bool {
            tap.consumeAuxiliary(data: key.rawValue << 16 | state << 8 | (repeatKey ? 1 : 0), flags: flags)
        }
        tap.apply = { key, fine in
            adjusted.append(key)
            fineStep = fine
            return key != .soundDown
        }
        return send(.displayUp, flags: [.maskShift, .maskAlternate]) && fineStep
            && send(.displayUp, repeatKey: true) && send(.displayUp, state: 0xB)
            && send(.mute) && send(.mute, repeatKey: true) && send(.mute, state: 0xB)
            && !send(.soundDown) && !send(.soundDown, repeatKey: true) && !send(.soundDown, state: 0xB)
            && !send(.soundUp, flags: .maskAlternate) && !send(.soundUp, state: 0xB)
            && !tap.consumeAuxiliary(data: 16 << 16 | 0xA << 8, flags: [])
            && adjusted == [.displayUp, .displayUp, .mute, .soundDown]
    }
}
