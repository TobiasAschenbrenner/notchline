import CoreAudio
import Foundation
import IOBluetooth

@MainActor
final class HeadphoneMonitor: NSObject {
    private let model: NotchModel
    private var connectObserver: IOBluetoothUserNotification?
    private var disconnectObservers: [String: IOBluetoothUserNotification] = [:]
    private var batteryReadTask: Task<Void, Never>?
    private var pendingBatteryDeviceName: String?

    init(model: NotchModel) {
        self.model = model
    }

    func startBluetoothMonitoring() {
        guard connectObserver == nil else { return }
        connectObserver = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []) where device.isConnected() {
            watchDisconnect(device)
        }
    }

    func stopBluetoothMonitoring() {
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
        guard connectObserver != nil else { return }
        watchDisconnect(device)
        presentBluetooth(device, connected: true)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let id = device.addressString { disconnectObservers.removeValue(forKey: id)?.unregister() }
        if connectObserver != nil { presentBluetooth(device, connected: false) }
    }

    private func presentBluetooth(_ device: IOBluetoothDevice, connected: Bool) {
        guard let name = device.name else { return }
        let output = SoundOutput(id: 0, source: nil, name: name, transport: kAudioDeviceTransportTypeBluetooth, volume: nil, muted: false)
        guard output.isHeadphones || device.deviceClassMajor == 4 else { return }
        showConnection(name: name, icon: output.icon, connected: connected, device: device)
    }

    func cancelBatteryRead() {
        batteryReadTask?.cancel()
        batteryReadTask = nil
        pendingBatteryDeviceName = nil
    }

    func showConnection(name: String, icon: String, connected: Bool, device: IOBluetoothDevice? = nil) {
        let battery = connected ? device.flatMap(AccessoryBattery.deviceCharge) ?? PowerSources.accessoryCharge(named: name) : nil
        model.showHeadphones(name, icon: icon, connected: connected, battery: battery)
        guard connected else {
            if pendingBatteryDeviceName == name {
                cancelBatteryRead()
            }
            return
        }
        guard battery == nil, case .headphones(let shownName, _, true, nil) = model.alert, shownName == name,
              batteryReadTask == nil || pendingBatteryDeviceName != name else { return }
        batteryReadTask?.cancel()
        pendingBatteryDeviceName = name
        let address = device?.addressString
        batteryReadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            let cached = device.flatMap(AccessoryBattery.deviceCharge)
            let charge: Int?
            if let cached { charge = cached }
            else { charge = await AccessoryBattery.systemReportCharge(name: name, address: address) }
            guard !Task.isCancelled else { return }
            self.batteryReadTask = nil
            self.pendingBatteryDeviceName = nil
            if let charge { self.model.updateHeadphoneBattery(name, battery: charge) }
        }
    }
}
