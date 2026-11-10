import AudioToolbox
import CoreAudio
import Foundation

enum AudioOutputDevice {
    static func current() -> SoundOutput? {
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

    static func writeVolume(_ level: Float, to output: SoundOutput) -> Bool {
        let scope = kAudioDevicePropertyScopeOutput
        return Self.set(output.id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, level, scope: scope)
            || Self.set(output.id, kAudioDevicePropertyVolumeScalar, level, scope: scope)
            || [UInt32(1), 2].map { Self.set(output.id, kAudioDevicePropertyVolumeScalar, level, scope: scope, element: $0) }.contains(true)
    }

    static func setMuted(_ muted: Bool, on output: SoundOutput) -> Bool {
        let scope = kAudioDevicePropertyScopeOutput
        let value: UInt32 = muted ? 1 : 0
        return Self.set(output.id, kAudioDevicePropertyMute, value, scope: scope)
            || [UInt32(1), 2].map { Self.set(output.id, kAudioDevicePropertyMute, value, scope: scope, element: $0) }.contains(true)
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
}
