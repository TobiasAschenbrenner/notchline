import AppKit

enum DisplaySpaces {
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
