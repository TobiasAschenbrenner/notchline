import AppKit
import SwiftUI

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class NotchHostingView: NSHostingView<NotchView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
    private var locked = false
    private var fullscreen = false
    private var lastSpaceCheckAt: TimeInterval = -.infinity
    private var hover = NotchHover()
    private var isDraggingFromPanel = false
    private var scrollDistance: CGFloat = 0
    private var didHandleScrollGesture = false
    private var lastScrollTimestamp = -1.0

    private(set) var visible = true
    var canShowLevelHUD: Bool { visible && panel.isVisible && !locked && !fullscreen }

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
        guard pointerTimer == nil else { return }
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
        pointerTimer?.invalidate()
        pointerTimer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let movementMonitor { NSEvent.removeMonitor(movementMonitor) }
        localMonitor = nil
        movementMonitor = nil
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
        refreshSpaceVisibility()
    }

    func setVisible(_ value: Bool) {
        visible = value
        refreshSpaceVisibility()
    }

    func setLocked(_ locked: Bool) {
        self.locked = locked
        refreshSpaceVisibility()
    }

    func refreshSpaceVisibility() {
        lastSpaceCheckAt = ProcessInfo.processInfo.systemUptime
        fullscreen = screen.map { DisplaySpaces.isFullscreen(on: $0) } ?? false
        applyVisibility()
    }

    private func applyVisibility() {
        let shouldShow = visible && !locked && !fullscreen && screen != nil
        if model.isOverlayVisible != shouldShow { model.isOverlayVisible = shouldShow }
        if shouldShow {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            if panel.isVisible { panel.orderOut(nil) }
            panel.ignoresMouseEvents = true
            hover.reset()
            isDraggingFromPanel = false
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
        guard visible, !locked, screen != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastSpaceCheckAt >= 0.3 { refreshSpaceVisibility() }
        guard panel.isVisible, !fullscreen else { return }
        let presentation = NotchPresentation(model: model)
        let inside = containsPointer(in: presentation)
        if NSEvent.pressedMouseButtons & 1 == 0 { isDraggingFromPanel = false }

        if model.alert != nil {
            hover.reset()
            if !inside && !isDraggingFromPanel { model.endLevelHover() }
        } else if let expand = hover.expansion(inside: inside, expanded: model.isExpanded,
                                               dragging: isDraggingFromPanel, now: now) {
            if expand {
                refreshSpaceVisibility()
                guard panel.isVisible, !fullscreen else { return }
            }
            model.setExpanded(expand)
        }

        let shown = NotchPresentation(model: model)
        let hit = shown != .idle && containsPointer(in: shown)
        let ignore = !hit && !isDraggingFromPanel
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    private func handleLocal(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            isDraggingFromPanel = event.window === panel && model.isExpanded
        case .leftMouseUp:
            isDraggingFromPanel = false
        case .mouseMoved, .leftMouseDragged:
            updatePointer()
        case .scrollWheel:
            if event.window === panel && !model.isExpanded && model.alert == nil && model.showsCompactPlayback {
                handleScroll(event)
                return nil
            }
        default: break
        }
        return event
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) || event.timestamp - lastScrollTimestamp > 0.28 {
            scrollDistance = 0
            didHandleScrollGesture = false
        }
        lastScrollTimestamp = event.timestamp
        guard !didHandleScrollGesture, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        scrollDistance += event.scrollingDeltaX * (event.isDirectionInvertedFromDevice ? -1 : 1)
        guard abs(scrollDistance) >= (event.hasPreciseScrollingDeltas ? 23 : 2) else { return }
        didHandleScrollGesture = true
        media.control(scrollDistance < 0 ? .next : .previous)
    }
}
