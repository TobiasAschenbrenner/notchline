import AppKit
import SwiftUI

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class NotchHostingView: NSHostingView<NotchView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct NotchHover {
    private var enteredAt: TimeInterval?
    private var leftAt: TimeInterval?

    mutating func expansion(inside: Bool, expanded: Bool, dragging: Bool, now: TimeInterval) -> Bool? {
        if dragging {
            reset()
            return nil
        }
        if inside {
            leftAt = nil
            guard !expanded else { enteredAt = nil; return nil }
            let start = enteredAt ?? now
            enteredAt = start
            return now - start >= 0.085 ? true : nil
        }
        enteredAt = nil
        guard expanded else { leftAt = nil; return nil }
        let start = leftAt ?? now
        leftAt = start
        return now - start >= 0.14 ? false : nil
    }

    mutating func reset() {
        enteredAt = nil
        leftAt = nil
    }
}

@MainActor
final class NotchPanelController {
    private let model: NotchModel
    private let signals: SystemSignals
    private let media: MediaMonitor
    private let panel = NotchPanel(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: false
    )
    private var hosting: NotchHostingView?
    private var geometry = NotchGeometry.preview
    private var screen: NSScreen?
    private var pointerTimer: Timer?
    private var localMonitor: Any?
    private var movementMonitor: Any?
    private var spaceTransition: Task<Void, Never>?
    private var spaceSuspended = false
    private var locked = false
    private var fullscreen = false
    private var lastSpaceCheck: TimeInterval = -.infinity
    private var hover = NotchHover()
    private var beganInside = false
    private var gesture: CGFloat = 0
    private var gestureHandled = false
    private var lastScroll = -1.0

    private(set) var visible = true
    var canShowLevelHUD: Bool { visible && panel.isVisible && !locked && !spaceSuspended && !fullscreen }

    init(model: NotchModel, media: MediaMonitor, signals: SystemSignals) {
        self.model = model
        self.media = media
        self.signals = signals
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenNone]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
    }

    func start() {
        reposition()
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved]) {
            [weak self] event in self?.handleLocal(event) ?? event
        }
        movementMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
    }

    func stop() {
        spaceTransition?.cancel()
        pointerTimer?.invalidate()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let movementMonitor { NSEvent.removeMonitor(movementMonitor) }
        panel.orderOut(nil)
    }

    func reposition() {
        screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
        guard let screen else { applyVisibility(); return }

        let center: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0, right.minX > left.maxX {
            geometry = NotchGeometry(cameraWidth: right.minX - left.maxX, cameraHeight: screen.safeAreaInsets.top)
            center = (left.maxX + right.minX) / 2
        } else {
            geometry = NotchGeometry(cameraWidth: 168, cameraHeight: NSStatusBar.system.thickness)
            center = screen.frame.midX
        }
        let root = NotchView(model: model, media: media, signals: signals, geometry: geometry)
        if let hosting {
            hosting.rootView = root
        } else {
            let hosting = NotchHostingView(rootView: root)
            hosting.sizingOptions = []
            panel.contentView = hosting
            self.hosting = hosting
        }
        panel.setFrame(
            CGRect(x: center - geometry.panelWidth / 2, y: screen.frame.maxY - geometry.panelHeight,
                   width: geometry.panelWidth, height: geometry.panelHeight), display: true
        )
        updateSpace()
    }

    func setVisible(_ value: Bool) {
        visible = value
        updateSpace()
    }

    func setLocked(_ locked: Bool) {
        self.locked = locked
        updateSpace()
    }

    func spaceDidChange() {
        spaceSuspended = true
        applyVisibility()
        spaceTransition?.cancel()
        spaceTransition = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.spaceSuspended = false
            self.reposition()
        }
    }

    func updateSpace() {
        lastSpaceCheck = ProcessInfo.processInfo.systemUptime
        fullscreen = screen.map { DisplaySpaces.isFullscreen(on: $0) } ?? false
        applyVisibility()
    }

    private func applyVisibility() {
        let shouldShow = visible && !locked && !spaceSuspended && !fullscreen && screen != nil
        if model.presentationVisible != shouldShow { model.presentationVisible = shouldShow }
        if shouldShow {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            if panel.isVisible { panel.orderOut(nil) }
            panel.ignoresMouseEvents = true
            hover.reset()
            beganInside = false
            model.setExpanded(false)
        }
    }

    private func containsPointer(in presentation: NotchPresentation) -> Bool {
        let size = geometry.size(for: presentation)
        let pointer = NSEvent.mouseLocation
        let point = CGPoint(x: pointer.x - panel.frame.midX + size.width / 2, y: panel.frame.maxY - pointer.y)
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.contains(point) else { return false }
        return presentation == .idle || presentation.contour.path(in: bounds).contains(point)
    }

    private func updatePointer() {
        guard visible, !locked, !spaceSuspended, screen != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastSpaceCheck >= 0.3 { updateSpace() }
        guard panel.isVisible, !fullscreen else { return }
        let presentation = NotchPresentation(model: model)
        let inside = containsPointer(in: presentation)
        if NSEvent.pressedMouseButtons & 1 == 0 { beganInside = false }

        if model.alert != nil {
            hover.reset()
            if !inside && !beganInside { model.endLevelHover() }
        } else if let expand = hover.expansion(inside: inside, expanded: model.expanded,
                                               dragging: beganInside, now: now) {
            if expand {
                updateSpace()
                guard panel.isVisible, !fullscreen else { return }
            }
            model.setExpanded(expand)
        }

        let shown = NotchPresentation(model: model)
        let hit = shown != .idle && containsPointer(in: shown)
        let ignore = !hit && !beganInside
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            beganInside = event.window === panel && model.expanded
        case .leftMouseUp:
            beganInside = false
        case .mouseMoved, .leftMouseDragged:
            updatePointer()
        case .scrollWheel:
            if event.window === panel && !model.expanded && model.alert == nil && model.compactMusic {
                handleScroll(event)
                return nil
            }
        default: break
        }
        return event
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) || event.timestamp - lastScroll > 0.28 {
            gesture = 0
            gestureHandled = false
        }
        lastScroll = event.timestamp
        guard !gestureHandled, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        gesture += event.scrollingDeltaX * (event.isDirectionInvertedFromDevice ? -1 : 1)
        guard abs(gesture) >= (event.hasPreciseScrollingDeltas ? 23 : 2) else { return }
        gestureHandled = true
        media.control(gesture < 0 ? .next : .previous)
    }
}

private enum DisplaySpaces {
    private typealias Connection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static let connection: Connection? = {
        guard let skyLight, let symbol = dlsym(skyLight, "CGSMainConnectionID") else { return nil }
        return unsafeBitCast(symbol, to: Connection.self)
    }()
    private static let copySpaces: CopySpaces? = {
        guard let skyLight, let symbol = dlsym(skyLight, "CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopySpaces.self)
    }()

    static func isFullscreen(on screen: NSScreen) -> Bool {
        if let connection, let copySpaces,
           let spaces = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]],
           let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
           let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            let identifier = CFUUIDCreateString(nil, uuid) as String
            let display = spaces.first {
                ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(identifier) == .orderedSame
            } ?? spaces.first { $0["Display Identifier"] as? String == "Main" }
            if let space = display?["Current Space"] as? [String: Any], let type = space["type"] as? Int {
                return type == 4
            }
        }

        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let frame = CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY,
                           width: screen.frame.width, height: screen.frame.height)
        return windows.contains { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                  window[kCGWindowOwnerPID as String] as? Int32 != ProcessInfo.processInfo.processIdentifier,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(rect.minX - frame.minX) < 2 && abs(rect.maxX - frame.maxX) < 2
                && abs(rect.maxY - frame.maxY) < 2
                && rect.minY <= frame.minY + screen.safeAreaInsets.top + 2 && rect.minY >= frame.minY - 2
        }
    }
}
