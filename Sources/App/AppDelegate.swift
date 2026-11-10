import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.notch.refreshSpaceVisibility() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.notch.refreshSpaceVisibility() }
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
            let content = SettingsView(model: model, media: media, signals: signals, quit: { NSApp.terminate(nil) })
            settings = SettingsWindow.make(content: content)
        }
        NSApp.activate()
        settings?.makeKeyAndOrderFront(nil)
    }
}
