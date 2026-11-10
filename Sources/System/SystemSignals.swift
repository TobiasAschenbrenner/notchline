import AppKit
import CoreAudio
import Intents
import SwiftUI

@MainActor
final class SystemSignals: NSObject, ObservableObject {
    @Published private(set) var bluetoothEnabled = UserDefaults.standard.bool(forKey: "bluetoothConnections")
    @Published private(set) var controlError: String?
    @Published private(set) var replacesSystemHUD = false
    var canShowLevelHUD: (() -> Bool)?
    private let levelKeys = LevelKeyTap()
    private let displayBrightness = DisplayBrightness()
    private let headphones: HeadphoneMonitor
    private let model: NotchModel
    private var levelPollingTimer: Timer?
    private var systemPollingTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sound: SoundOutput?
    private var power: PowerState?

    init(model: NotchModel) {
        self.model = model
        self.headphones = HeadphoneMonitor(model: model)
    }

    func start() {
        updateDisplay()
        if bluetoothEnabled { headphones.startBluetoothMonitoring() }
        pollLevels()
        pollPowerAndFocus()
        levelKeys.apply = { [weak self] key, fine in self?.handleLevelKey(key, fine: fine) ?? false }
        refreshLevelKeyTap()
        levelPollingTimer = timer(interval: 0.10, tolerance: 0.02) { [weak self] in self?.pollLevels() }
        systemPollingTimer = timer(interval: 3, tolerance: 0.5) { [weak self] in
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
        headphones.stopBluetoothMonitoring()
        levelKeys.stop()
        headphones.cancelBatteryRead()
        levelPollingTimer?.invalidate()
        systemPollingTimer?.invalidate()
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
            guard let level = displayBrightness.currentLevel() else { return false }
            let next = key.nextLevel(from: level, fine: fine)
            guard next == level || displayBrightness.setLevel(next) else { return false }
            model.show(.brightness(next), pulseLimit: key == .displayUp && level == 1)
        } else {
            guard let output = AudioOutputDevice.current(), let level = output.volume else { return false }
            let muted = key == .mute && !output.muted
            let next = key == .mute ? level : key.nextLevel(from: output.muted ? 0 : level, fine: fine)
            if key == .mute {
                guard AudioOutputDevice.setMuted(muted, on: output) else { return false }
            } else {
                let unmuted = !output.muted || next == 0 || AudioOutputDevice.setMuted(false, on: output)
                guard unmuted else { return false }
                if next != level, !AudioOutputDevice.writeVolume(Float(next), to: output) {
                    if output.muted, next > 0 { _ = AudioOutputDevice.setMuted(true, on: output) }
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
        let nextAudioOutput = AudioOutputDevice.current()
        if sound != nextAudioOutput {
            defer { sound = nextAudioOutput }
            model.output = nextAudioOutput
            if let sound, let next = nextAudioOutput, next.id != sound.id || next.source != sound.source,
               next.isPersonalAudio, !bluetoothEnabled || next.transport == kAudioDeviceTransportTypeBuiltIn {
                headphones.showConnection(name: next.routeName, icon: next.icon, connected: true)
            }
        }

        let nextBrightness = displayBrightness.currentLevel()
        if model.brightness != nextBrightness { model.brightness = nextBrightness }
    }

    private func pollPowerAndFocus() {
        if let next = PowerSources.currentBattery(), power != next {
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
        displayBrightness.refreshDisplay()
    }

    func setVolume(_ value: Double) {
        guard value.isFinite, let output = AudioOutputDevice.current(), output.volume != nil else { return }
        let level = Float(min(1, max(0, value)))
        let adjusted = AudioOutputDevice.writeVolume(level, to: output)
        if adjusted && output.muted && level > 0 { _ = AudioOutputDevice.setMuted(false, on: output) }
        controlError = adjusted ? nil : "This audio output manages its own volume."
        pollLevels()
        if adjusted, !model.outputVolumeOpen, let current = model.output, let volume = current.volume,
           current.id == output.id, current.source == output.source,
           current.volume != output.volume || current.muted != output.muted {
            model.show(.volume(volume, muted: current.muted))
        }
    }

    func setBrightness(_ value: Double) {
        guard value.isFinite, displayBrightness.hasDisplay else { return }
        let level = min(1, max(0, value))
        guard displayBrightness.setLevel(level) else {
            controlError = "Brightness is unavailable for this display."
            return
        }
        controlError = nil
        pollLevels()
        model.show(.brightness(level))
    }

    func setBluetoothEnabled(_ enabled: Bool) {
        bluetoothEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "bluetoothConnections")
        if enabled { headphones.startBluetoothMonitoring() } else { headphones.stopBluetoothMonitoring() }
    }
}
