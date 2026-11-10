import AppKit
import SwiftUI

@MainActor
enum SettingsWindow {
    static func make(content: SettingsView) -> NSWindow {
        let bounds = CGRect(origin: .zero, size: SettingsView.windowSize)
        let window = NSWindow(
            contentRect: bounds,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Notchline Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = backdrop(containing: hostingView)
        window.center()
        return window
    }

    private static func backdrop(containing hostingView: NSView) -> NSView {
        let bounds = hostingView.bounds
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            glass.cornerRadius = 16
            glass.contentView = hostingView
            return glass
        }
        #endif
        let material = NSVisualEffectView(frame: bounds)
        material.material = .underWindowBackground
        material.blendingMode = .behindWindow
        material.addSubview(hostingView)
        return material
    }
}
