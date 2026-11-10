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

    init?(brightnessKeyCode: Int64) {
        switch brightnessKeyCode {
        case 144: self = .displayUp
        case 145: self = .displayDown
        default: return nil
        }
    }
}

@MainActor
final class LevelKeyTap {
    private static let systemDefined = UInt32(NSEvent.EventType.systemDefined.rawValue)
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var handled: Set<LevelKey> = []
    var apply: ((LevelKey, Bool) -> Bool)?
    var isRunning: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {
        guard port == nil, AXIsProcessTrusted() else { return }
        let systemDefined = CGEventMask(1) << Self.systemDefined
        let mask = systemDefined | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            MainActor.assumeIsolated {
                guard let context else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<LevelKeyTap>.fromOpaque(context).takeUnretainedValue()
                return listener.consume(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        func makeTap(at location: CGEventTapLocation) -> CFMachPort? {
            CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                              eventsOfInterest: mask, callback: callback, userInfo: context)
        }
        // Filter hardware keys as early as macOS allows, before system shortcut handling.
        guard let port = makeTap(at: .cghidEventTap) ?? makeTap(at: .cgSessionEventTap),
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
        if type.rawValue == Self.systemDefined {
            guard let keyboard = NSEvent(cgEvent: event), keyboard.type == .systemDefined,
                  keyboard.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS else { return false }
            return consumeAuxiliary(data: keyboard.data1, flags: event.flags)
        }
        guard type == .keyDown || type == .keyUp,
              let key = LevelKey(brightnessKeyCode: event.getIntegerValueField(.keyboardEventKeycode)) else { return false }
        return consume(key, pressed: type == .keyDown,
                       repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, flags: event.flags)
    }

    func consumeAuxiliary(data: Int, flags: CGEventFlags) -> Bool {
        guard let key = LevelKey(rawValue: (data >> 16) & 0xFFFF) else { return false }
        let state = (data >> 8) & 0xFF
        guard state == NX_KEYDOWN || state == NX_KEYUP else { return false }
        return consume(key, pressed: state == NX_KEYDOWN, repeated: data & 1 != 0, flags: flags)
    }

    private func consume(_ key: LevelKey, pressed: Bool, repeated: Bool, flags: CGEventFlags) -> Bool {
        if !pressed { return handled.remove(key) != nil }
        if repeated {
            guard handled.contains(key) else { return false }
            if key == .mute { return true }
        }
        let fine = flags.contains([.maskShift, .maskAlternate])
        // Option alone opens the matching System Settings page.
        guard !flags.contains(.maskCommand), !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) || fine, apply?(key, fine) == true else {
            handled.remove(key)
            return false
        }
        handled.insert(key)
        return true
    }
}
