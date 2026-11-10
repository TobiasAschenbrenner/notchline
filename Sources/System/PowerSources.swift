import Foundation
import IOKit.ps

enum PowerSources {
    static func accessoryCharge(named name: String) -> Int? {
        for details in descriptions() {
            guard details[kIOPSTypeKey] as? String != kIOPSInternalBatteryType,
                  let sourceName = details[kIOPSNameKey] as? String,
                  sourceName.caseInsensitiveCompare(name) == .orderedSame,
                  let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = details[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0, (0...maximum).contains(current) else { continue }
            return Int((100 * Double(current) / Double(maximum)).rounded())
        }
        return nil
    }

    static func currentBattery() -> PowerState? {
        for details in descriptions() {
            guard details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return PowerState(
                percentage: min(100, max(0, Int((100 * Double(current) / Double(maximum)).rounded()))),
                pluggedIn: details[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        }
        return nil
    }

    private static func descriptions() -> [[String: Any]] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [AnyObject] else { return [] }
        return sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
    }
}
