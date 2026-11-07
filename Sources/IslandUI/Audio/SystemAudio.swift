import CoreAudio
import Darwin
import Foundation
import IslandCore

/// What the mixer needs to know about the Mac's sound. The real one asks CoreAudio; tests use a stand-in.
protocol AudioSystem: AnyObject {
    /// The volume of the sound output (0 to 1), nil when this output has no volume control (some HDMI and USB devices).
    func outputVolume() -> Float?
    func setOutputVolume(_ value: Float)
    /// Every program the system lists as using audio.
    func clients() -> [AudioClient]
}

/// CoreAudio, asked directly. Reading is always safe; the only thing this changes is the output volume.
final class CoreAudioSystem: AudioSystem {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    // MARK: Output volume

    func outputVolume() -> Float? {
        guard let device = Self.defaultOutputDevice() else { return nil }
        if let main = Self.volume(of: device, element: kAudioObjectPropertyElementMain) { return main }
        // Some devices have no overall volume, only one per channel.
        let channels = [Self.volume(of: device, element: 1), Self.volume(of: device, element: 2)].compactMap { $0 }
        return channels.isEmpty ? nil : channels.reduce(0, +) / Float(channels.count)
    }

    func setOutputVolume(_ value: Float) {
        guard let device = Self.defaultOutputDevice() else { return }
        let clamped = min(max(value, 0), 1)
        if Self.hasVolume(device, element: kAudioObjectPropertyElementMain) {
            Self.setVolume(clamped, on: device, element: kAudioObjectPropertyElementMain)
        } else {
            for element: AudioObjectPropertyElement in [1, 2] where Self.hasVolume(device, element: element) {
                Self.setVolume(clamped, on: device, element: element)
            }
        }
    }

    // MARK: Who is making sound

    func clients() -> [AudioClient] {
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(Self.system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &objects) == noErr else { return [] }

        return objects.compactMap { object in
            guard let rawPID = Self.uint32(object, kAudioProcessPropertyPID) else { return nil }
            let pid = Int32(bitPattern: rawPID)
            return AudioClient(
                processObject: object, pid: pid, path: Self.path(of: pid),
                isPlaying: (Self.uint32(object, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0)
        }
    }

    // MARK: Helpers (also used by the per-app volume code)

    static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// The unique name CoreAudio gives the current output device.
    static func defaultOutputUID() -> String? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func path(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }

    private static func hasVolume(_ device: AudioObjectID, element: AudioObjectPropertyElement) -> Bool {
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func volume(of device: AudioObjectID, element: AudioObjectPropertyElement) -> Float? {
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setVolume(_ value: Float, on device: AudioObjectID, element: AudioObjectPropertyElement) {
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}
