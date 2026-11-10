import AppKit

@MainActor
final class DisplayBrightness {
    private typealias BrightnessWriter = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias BrightnessReader = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private lazy var readBrightness: BrightnessReader? = {
        guard let displayServices, let symbol = dlsym(displayServices, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: BrightnessReader.self)
    }()
    private lazy var writeBrightness: BrightnessWriter? = {
        guard let displayServices, let symbol = dlsym(displayServices, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: BrightnessWriter.self)
    }()
    private typealias UserBrightnessReader = @convention(c) (CGDirectDisplayID) -> Double
    private typealias UserBrightnessWriter = @convention(c) (CGDirectDisplayID, Double) -> Void
    private let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
    private lazy var readUserBrightness: UserBrightnessReader? = {
        guard let coreDisplay, let symbol = dlsym(coreDisplay, "CoreDisplay_Display_GetUserBrightness") else { return nil }
        return unsafeBitCast(symbol, to: UserBrightnessReader.self)
    }()
    private lazy var writeUserBrightness: UserBrightnessWriter? = {
        guard let coreDisplay, let symbol = dlsym(coreDisplay, "CoreDisplay_Display_SetUserBrightness") else { return nil }
        return unsafeBitCast(symbol, to: UserBrightnessWriter.self)
    }()
    private var displayID: CGDirectDisplayID?
    var hasDisplay: Bool { displayID != nil }

    func refreshDisplay() {
        let main = CGMainDisplayID()
        let builtIn = NSScreen.screens
            .compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
            .first { CGDisplayIsBuiltin($0) != 0 } ?? (CGDisplayIsBuiltin(main) != 0 ? main : nil)
        displayID = builtIn
    }

    func currentLevel() -> Double? {
        guard let display = displayID else { return nil }
        var value: Float = 0
        if let readBrightness, readBrightness(display, &value) == 0, value.isFinite, (0...1).contains(value) {
            return Double(value)
        }
        guard let fallback = readUserBrightness?(display), fallback.isFinite, (0...1).contains(fallback) else { return nil }
        return fallback
    }

    func setLevel(_ level: Double) -> Bool {
        guard let display = displayID else { return false }
        if writeBrightness?(display, Float(level)) == 0 { return true }
        guard let writeUserBrightness, readUserBrightness != nil else { return false }
        writeUserBrightness(display, level)
        return true
    }
}
