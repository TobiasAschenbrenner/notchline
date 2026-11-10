import Foundation
import IOBluetooth
import ObjectiveC.runtime

enum AccessoryBattery {
    static func deviceCharge(_ device: IOBluetoothDevice) -> Int? {
        let left = batteryValue("batteryPercentLeft", on: device)
        let right = batteryValue("batteryPercentRight", on: device)
        return [left, right].compactMap { $0 }.min()
            ?? batteryValue("batteryPercentSingle", on: device)
            ?? batteryValue("batteryPercentCombined", on: device)
    }

    private static func batteryValue(_ property: String, on device: IOBluetoothDevice) -> Int? {
        let selector = NSSelectorFromString(property)
        guard let cls = object_getClass(device), let method = class_getInstanceMethod(cls, selector) else { return nil }
        let type = method_copyReturnType(method)
        defer { free(type) }
        // Some Apple headsets expose cached charge on IOBluetoothDevice as an unsigned byte.
        guard String(cString: type) == "C" else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
        let read = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let value = Int(read(device, selector))
        return (1...100).contains(value) ? value : nil
    }

    static func systemReportCharge(name: String, address: String?) async -> Int? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["-timeout", "3", "SPBluetoothDataType", "-json"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil as Int? }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return charge(in: data, name: name, address: address)
        }.value
    }

    static func charge(in data: Data, name: String, address: String?) -> Int? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        let connected = controllers.flatMap { $0["device_connected"] as? [[String: Any]] ?? [] }
        let wantedAddress = address.map(normalizedAddress)
        var values: [Int] = []
        for entry in connected {
            for (deviceName, details) in entry {
                guard let info = details as? [String: Any] else { continue }
                if let wantedAddress, let reported = info["device_address"] as? String {
                    guard wantedAddress == normalizedAddress(reported) else { continue }
                } else if deviceName.caseInsensitiveCompare(name) != .orderedSame {
                    continue
                }

                let buds = ["device_batteryLevelLeft", "device_batteryLevelRight"].compactMap { percent(info[$0]) }
                if let value = buds.min() ?? percent(info["device_batteryLevelMain"]) {
                    values.append(value)
                }
            }
        }
        return values.count == 1 ? values.first : nil
    }

    private static func percent(_ value: Any?) -> Int? {
        let number: Int?
        if let value = value as? String {
            number = Int(value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "%"))))
        } else {
            number = value as? Int
        }
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }

    private static func normalizedAddress(_ value: String) -> String {
        value.lowercased().filter { $0.isHexDigit }
    }
}
