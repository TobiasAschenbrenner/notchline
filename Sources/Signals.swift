import AppKit
import AudioToolbox
import CoreAudio
import IOBluetooth
import IOKit.ps
import SwiftUI
import Intents

struct SoundOutput: Equatable {
    let id: AudioDeviceID
    let source: UInt32?
    let name: String
    let transport: UInt32?
    let volume: Double?
    let muted: Bool

    var isHeadphones: Bool {
        let label = name.lowercased()
        return source == 0x6864706e || label.contains("headphone") || label.contains("airpods")
            || label.contains("beats") || label.contains("earbuds") || label.contains("earphones")
    }

    var isPersonalAudio: Bool {
        isHeadphones || transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    var icon: String {
        if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
        if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
        if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
        return isHeadphones ? "headphones" : "speaker.wave.2.fill"
    }

    var playerIcon: String { isPersonalAudio ? icon : "laptopcomputer" }

    var routeName: String {
        source == 0x6864706e && !name.localizedCaseInsensitiveContains("headphone") ? "Headphones" : name
    }
}

struct PowerState: Equatable {
    let percentage: Int
    let pluggedIn: Bool
    let lowPower: Bool

    var low: Bool { !pluggedIn && percentage <= 20 }

    func crossedWarning(from prior: PowerState?) -> Bool {
        guard !pluggedIn else { return false }
        if prior == nil || prior?.pluggedIn == true { return low }
        guard let prior else { return false }
        return [20, 10, 5].contains { prior.percentage > $0 && percentage <= $0 }
    }

    var icon: String {
        if pluggedIn { return "battery.100percent.bolt" }
        switch percentage {
        case 76...100: return "battery.100percent"
        case 51...75: return "battery.75percent"
        case 26...50: return "battery.50percent"
        default: return "battery.25percent"
        }
    }
}

@MainActor
final class SystemSignals: NSObject, ObservableObject {
    @Published private(set) var bluetoothEnabled = UserDefaults.standard.bool(forKey: "bluetoothConnections")
    @Published private(set) var controlError: String?
    @Published private(set) var replacesSystemHUD = false
    var canShowLevelHUD: (() -> Bool)?
    private let levelKeys = LevelKeyTap()
    private var connectObserver: IOBluetoothUserNotification?
    private var disconnectObservers: [String: IOBluetoothUserNotification] = [:]
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
    private var batteryRead: Task<Void, Never>?
    private var batteryDeviceName: String?
    private let model: NotchModel
    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sound: SoundOutput?
    private var displayID: CGDirectDisplayID?
    private var power: PowerState?

    init(model: NotchModel) { self.model = model }

    func start() {
        updateDisplay()
        if bluetoothEnabled { startBluetooth() }
        pollLevels()
        pollPowerAndFocus()
        levelKeys.apply = { [weak self] key, fine in self?.handleLevelKey(key, fine: fine) ?? false }
        refreshLevelKeyTap()
        fastTimer = timer(interval: 0.10, tolerance: 0.02) { [weak self] in self?.pollLevels() }
        slowTimer = timer(interval: 3, tolerance: 0.5) { [weak self] in
            self?.pollPowerAndFocus()
            self?.refreshLevelKeyTap()
        }

        for (name, enabled) in [("_NSDoNotDisturbEnabledNotification", true), ("_NSDoNotDisturbDisabledNotification", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.updateFocus(enabled) }
            })
        }
    }

    func stop() {
        stopBluetooth()
        levelKeys.stop()
        batteryRead?.cancel()
        fastTimer?.invalidate()
        slowTimer?.invalidate()
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers.removeAll()
    }

    func openAccessibilitySettings() {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        refreshLevelKeyTap()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshLevelKeyTap() {
        if AXIsProcessTrusted(), model.levelAlerts {
            if !levelKeys.isRunning {
                levelKeys.stop()
                levelKeys.start()
            }
        } else {
            levelKeys.stop()
        }
        if replacesSystemHUD != levelKeys.isRunning { replacesSystemHUD = levelKeys.isRunning }
    }

    private func handleLevelKey(_ key: LevelKey, fine: Bool) -> Bool {
        guard model.levelAlerts, canShowLevelHUD?() == true else { return false }
        if key.isDisplay {
            guard let displayID, let level = currentBrightness() else { return false }
            let next = key.nextLevel(from: level, fine: fine)
            guard next == level || writeDisplayBrightness(next, to: displayID) else { return false }
            model.show(.brightness(next), pulseLimit: key == .displayUp && level == 1)
        } else {
            guard let output = Self.currentSound(), let level = output.volume else { return false }
            let muted = key == .mute && !output.muted
            let next = key == .mute ? level : key.nextLevel(from: output.muted ? 0 : level, fine: fine)
            if key == .mute {
                guard setMute(muted, on: output) else { return false }
            } else {
                let unmuted = !output.muted || next == 0 || setMute(false, on: output)
                guard unmuted else { return false }
                if next != level, !writeVolume(Float(next), to: output) {
                    if output.muted, next > 0 { _ = setMute(true, on: output) }
                    return false
                }
            }
            model.show(.volume(next, muted: muted || (output.muted && key != .mute && next == 0)),
                       pulseLimit: key == .soundUp && !output.muted && level == 1)
        }
        return true
    }

    func requestFocusAccess() {
        INFocusStatusCenter.default.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.model.focusAccess = status == .authorized ? "Focus sharing enabled" : "Focus sharing unavailable"
                self?.pollPowerAndFocus()
            }
        }
    }

    private func timer(interval: TimeInterval, tolerance: TimeInterval, action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func pollLevels() {
        // A key passed to macOS can already produce a native indicator. Polling
        // keeps settings current without presenting a second indicator.
        let nextSound = Self.currentSound()
        if sound != nextSound {
            defer { sound = nextSound }
            model.output = nextSound
            if let sound, let next = nextSound, next.id != sound.id || next.source != sound.source,
               next.isPersonalAudio, !bluetoothEnabled || next.transport == kAudioDeviceTransportTypeBuiltIn {
                showHeadphones(name: next.routeName, icon: next.icon, connected: true)
            }
        }

        let nextBrightness = currentBrightness()
        if model.brightness != nextBrightness { model.brightness = nextBrightness }
    }

    private func pollPowerAndFocus() {
        if let next = Self.currentPower(), power != next {
            defer { power = next }
            model.power = next
            if next.crossedWarning(from: power) {
                model.show(.power(next, title: next.percentage <= 5 ? "Critical battery" : "Low battery"))
            } else if let power, power.pluggedIn != next.pluggedIn {
                model.show(.power(next, title: next.pluggedIn ? "Power connected" : "On battery"))
            }
        }

        let center = INFocusStatusCenter.default
        if center.authorizationStatus == .authorized {
            if model.focusAccess.isEmpty { model.focusAccess = "Focus sharing enabled" }
            if let status = center.focusStatus.isFocused {
                model.updateFocus(status)
            }
        }
    }

    func updateDisplay() {
        let main = CGMainDisplayID()
        let builtIn = NSScreen.screens
            .compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
            .first { CGDisplayIsBuiltin($0) != 0 } ?? (CGDisplayIsBuiltin(main) != 0 ? main : nil)
        displayID = builtIn
    }

    private func currentBrightness() -> Double? {
        guard let display = displayID else { return nil }
        var value: Float = 0
        if let readBrightness, readBrightness(display, &value) == 0, value.isFinite, (0...1).contains(value) {
            return Double(value)
        }
        guard let fallback = readUserBrightness?(display), fallback.isFinite, (0...1).contains(fallback) else { return nil }
        return fallback
    }

    func setVolume(_ value: Double) {
        guard value.isFinite, let output = Self.currentSound(), output.volume != nil else { return }
        let level = Float(min(1, max(0, value)))
        let adjusted = writeVolume(level, to: output)
        if adjusted && output.muted && level > 0 { _ = setMute(false, on: output) }
        controlError = adjusted ? nil : "This audio output manages its own volume."
        pollLevels()
        if adjusted, !model.outputVolumeOpen, let current = model.output, let volume = current.volume,
           current.id == output.id, current.source == output.source,
           current.volume != output.volume || current.muted != output.muted {
            model.show(.volume(volume, muted: current.muted))
        }
    }

    private func writeVolume(_ level: Float, to output: SoundOutput) -> Bool {
        let scope = kAudioDevicePropertyScopeOutput
        return Self.set(output.id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, level, scope: scope)
            || Self.set(output.id, kAudioDevicePropertyVolumeScalar, level, scope: scope)
            || [UInt32(1), 2].map { Self.set(output.id, kAudioDevicePropertyVolumeScalar, level, scope: scope, element: $0) }.contains(true)
    }

    private func setMute(_ muted: Bool, on output: SoundOutput) -> Bool {
        let scope = kAudioDevicePropertyScopeOutput
        let value: UInt32 = muted ? 1 : 0
        return Self.set(output.id, kAudioDevicePropertyMute, value, scope: scope)
            || [UInt32(1), 2].map { Self.set(output.id, kAudioDevicePropertyMute, value, scope: scope, element: $0) }.contains(true)
    }

    func setBrightness(_ value: Double) {
        guard value.isFinite, let displayID else { return }
        let level = min(1, max(0, value))
        guard writeDisplayBrightness(level, to: displayID) else {
            controlError = "Brightness is unavailable for this display."
            return
        }
        controlError = nil
        pollLevels()
        model.show(.brightness(level))
    }

    private func writeDisplayBrightness(_ level: Double, to display: CGDirectDisplayID) -> Bool {
        if writeBrightness?(display, Float(level)) == 0 { return true }
        guard let writeUserBrightness, readUserBrightness != nil else { return false }
        writeUserBrightness(display, level)
        return true
    }

    func setBluetoothEnabled(_ enabled: Bool) {
        bluetoothEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "bluetoothConnections")
        if enabled { startBluetooth() } else { stopBluetooth() }
    }

    private func startBluetooth() {
        guard connectObserver == nil else { return }
        connectObserver = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []) where device.isConnected() {
            watchDisconnect(device)
        }
    }

    private func stopBluetooth() {
        connectObserver?.unregister()
        connectObserver = nil
        for token in disconnectObservers.values { token.unregister() }
        disconnectObservers.removeAll()
    }

    private func watchDisconnect(_ device: IOBluetoothDevice) {
        guard let id = device.addressString, disconnectObservers[id] == nil else { return }
        disconnectObservers[id] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard bluetoothEnabled else { return }
        watchDisconnect(device)
        presentBluetooth(device, connected: true)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let id = device.addressString { disconnectObservers.removeValue(forKey: id)?.unregister() }
        if bluetoothEnabled { presentBluetooth(device, connected: false) }
    }

    private func presentBluetooth(_ device: IOBluetoothDevice, connected: Bool) {
        guard let name = device.name else { return }
        let output = SoundOutput(id: 0, source: nil, name: name, transport: kAudioDeviceTransportTypeBluetooth, volume: nil, muted: false)
        guard output.isHeadphones || device.deviceClassMajor == 4 else { return }
        showHeadphones(name: name, icon: output.icon, connected: connected, device: device)
    }

    private func showHeadphones(name: String, icon: String, connected: Bool, device: IOBluetoothDevice? = nil) {
        let battery = connected ? device.flatMap(AccessoryBattery.deviceCharge) ?? Self.accessoryCharge(name) : nil
        model.showHeadphones(name, icon: icon, connected: connected, battery: battery)
        guard connected else {
            if batteryDeviceName == name {
                batteryRead?.cancel()
                batteryRead = nil
                batteryDeviceName = nil
            }
            return
        }
        guard battery == nil, case .headphones(let shownName, _, true, nil) = model.alert, shownName == name,
              batteryRead == nil || batteryDeviceName != name else { return }
        batteryRead?.cancel()
        batteryDeviceName = name
        let address = device?.addressString
        batteryRead = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let cached = device.flatMap(AccessoryBattery.deviceCharge)
            let charge: Int?
            if let cached { charge = cached }
            else { charge = await AccessoryBattery.systemReportCharge(name: name, address: address) }
            guard !Task.isCancelled else { return }
            self.batteryRead = nil
            self.batteryDeviceName = nil
            if let charge { self.model.updateHeadphoneBattery(name, battery: charge) }
        }
    }

    private static func set<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T,
                               scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var property = address(selector, scope: scope, element: element)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &property, &settable) == noErr, settable.boolValue else { return false }
        return withUnsafeBytes(of: value) { bytes in
            guard let buffer = bytes.baseAddress else { return false }
            return AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(bytes.count), buffer) == noErr
        }
    }

    private static func audioName(_ device: AudioDeviceID) -> String? {
        var nameAddress = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout.size(ofValue: name))
        guard AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    static func currentSound() -> SoundOutput? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let device = uintProperty(system, kAudioHardwarePropertyDefaultOutputDevice), device != kAudioObjectUnknown else {
            return nil
        }

        let scope = kAudioDevicePropertyScopeOutput
        let source = uintProperty(device, kAudioDevicePropertyDataSource, scope: scope)
        let transport = uintProperty(device, kAudioDevicePropertyTransportType)
        let master = floatProperty(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
            ?? floatProperty(device, kAudioDevicePropertyVolumeScalar)
        let volume = master ?? [UInt32(1), 2].compactMap { floatProperty(device, kAudioDevicePropertyVolumeScalar, element: $0) }.max()
        let masterMute = uintProperty(device, kAudioDevicePropertyMute, scope: scope)
        let channelMutes = [UInt32(1), 2].compactMap { uintProperty(device, kAudioDevicePropertyMute, scope: scope, element: $0) }
        let muted = masterMute.map { $0 != 0 } ?? (!channelMutes.isEmpty && channelMutes.allSatisfy { $0 != 0 })
        return SoundOutput(
            id: device, source: source,
            name: audioName(device) ?? "Audio output",
            transport: transport, volume: volume.map(Double.init), muted: muted
        )
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func uintProperty(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> UInt32? {
        var property = address(selector, scope: scope, element: element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectHasProperty(device, &property),
              AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func floatProperty(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                      element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Float? {
        var property = address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
        var value: Float = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectHasProperty(device, &property),
              AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr,
              value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    private static func accessoryCharge(_ name: String) -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [AnyObject] else { return nil }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  details[kIOPSTypeKey] as? String != kIOPSInternalBatteryType,
                  let sourceName = details[kIOPSNameKey] as? String,
                  sourceName.caseInsensitiveCompare(name) == .orderedSame,
                  let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = details[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0, (0...maximum).contains(current) else { continue }
            return Int((100 * Double(current) / Double(maximum)).rounded())
        }
        return nil
    }

    static func currentPower() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [AnyObject] else { return nil }
        for source in sources {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
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
}
