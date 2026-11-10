import AppKit
import IOKit.hidsystem

enum LevelKey: Int, Hashable {
    case soundUp = 0, soundDown = 1, displayUp = 2, displayDown = 3, mute = 7

    var isDisplay: Bool { self == .displayUp || self == .displayDown }

    func nextLevel(from level: Double, fine: Bool) -> Double {
        let steps = fine ? 64.0 : 16.0
        let scaled = (level * steps * 1_000).rounded() / 1_000
        let up = self == .soundUp || self == .displayUp
        let next = up ? floor(scaled) + 1 : ceil(scaled) - 1
        return min(1, max(0, next / steps))
    }

    init?(event: NSEvent) {
        if event.type == .systemDefined, event.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS {
            self.init(rawValue: (event.data1 >> 16) & 0xFFFF)
        } else if event.type == .keyDown || event.type == .keyUp {
            switch event.keyCode {
            case 144: self = .displayUp
            case 145: self = .displayDown
            default: return nil
            }
        } else { return nil }
    }
}

@MainActor
final class LevelKeyTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var handled: Set<LevelKey> = []
    var apply: ((LevelKey, Bool) -> Bool)?
    var isRunning: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {
        guard port == nil, AXIsProcessTrusted() else { return }
        let systemDefined = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue
        let mask = systemDefined | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: mask,
                                           callback: { _, type, event, context in
            MainActor.assumeIsolated {
                guard let context else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<LevelKeyTap>.fromOpaque(context).takeUnretainedValue()
                return listener.consume(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        source = nil
        port = nil
        handled.removeAll()
    }

    private func consume(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handled.removeAll()
            if let port, AXIsProcessTrusted() { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        }
        guard let keyboard = NSEvent(cgEvent: event), let key = LevelKey(event: keyboard) else { return false }
        let system = keyboard.type == .systemDefined
        let state = system ? (keyboard.data1 >> 8) & 0xFF : (type == .keyDown ? 0xA : 0xB)
        if state == 0xB { return handled.remove(key) != nil }
        guard state == 0xA else { return false }

        let modifiers = keyboard.modifierFlags
        let fine = modifiers.contains([.shift, .option])
        // Option alone opens the matching System Settings page.
        guard !modifiers.contains(.command), !modifiers.contains(.control),
              !modifiers.contains(.option) || fine else { return false }
        let repeated = system ? keyboard.data1 & 1 == 1 : keyboard.isARepeat
        if key == .mute, repeated { return handled.contains(key) }
        guard apply?(key, fine) == true else { return false }
        handled.insert(key)
        return true
    }
}
