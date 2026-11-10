import CoreAudio
import Foundation

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
