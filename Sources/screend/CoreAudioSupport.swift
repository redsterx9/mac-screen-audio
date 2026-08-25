import Foundation
import CoreAudio
import AudioToolbox

/// Thin wrappers over the AudioObject property API. Nothing here mutates state —
/// these are read-only lookups used for reporting and for finding the current output device.
enum CA {

    static func addr(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
    -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func value<T>(_ object: AudioObjectID,
                         _ address: AudioObjectPropertyAddress,
                         initial: T) -> T? {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        var out = initial
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &out)
        return status == noErr ? out : nil
    }

    static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cf: CFString? = nil
        let status = withUnsafeMutablePointer(to: &cf) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let cf else { return nil }
        return cf as String
    }

    static func objectIDs(_ object: AudioObjectID,
                          _ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0
        else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    // MARK: - Devices

    static var allDevices: [AudioObjectID] {
        objectIDs(AudioObjectID(kAudioObjectSystemObject), addr(kAudioHardwarePropertyDevices))
    }

    static func uid(of device: AudioObjectID) -> String? {
        string(device, addr(kAudioDevicePropertyDeviceUID))
    }

    static func name(of device: AudioObjectID) -> String? {
        string(device, addr(kAudioObjectPropertyName))
    }

    static func channelCount(of device: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = addr(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0
        else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr
        else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func sampleRate(of device: AudioObjectID) -> Double {
        value(device, addr(kAudioDevicePropertyNominalSampleRate), initial: Double(0)) ?? 0
    }

    static func transportType(of device: AudioObjectID) -> UInt32 {
        value(device, addr(kAudioDevicePropertyTransportType), initial: UInt32(0)) ?? 0
    }

    /// The Mac's own speakers. Preferred as the aggregate's clock because they are always
    /// present — an audio interface can be unplugged mid-session, and picking it would also
    /// drag it into the aggregate for no reason.
    static var builtInOutputDevice: AudioObjectID? {
        allDevices.first {
            transportType(of: $0) == kAudioDeviceTransportTypeBuiltIn
                && channelCount(of: $0, scope: kAudioObjectPropertyScopeOutput) > 0
        }
    }

    static func device(forUID uid: String) -> AudioObjectID? {
        allDevices.first { self.uid(of: $0) == uid }
    }

    // MARK: - Defaults (read-only — screend never writes these)

    static var defaultOutputDevice: AudioObjectID? {
        let id = value(AudioObjectID(kAudioObjectSystemObject),
                       addr(kAudioHardwarePropertyDefaultOutputDevice),
                       initial: AudioObjectID(0))
        return (id ?? 0) == 0 ? nil : id
    }

    static var defaultInputDevice: AudioObjectID? {
        let id = value(AudioObjectID(kAudioObjectSystemObject),
                       addr(kAudioHardwarePropertyDefaultInputDevice),
                       initial: AudioObjectID(0))
        return (id ?? 0) == 0 ? nil : id
    }

    static var defaultSystemOutputDevice: AudioObjectID? {
        let id = value(AudioObjectID(kAudioObjectSystemObject),
                       addr(kAudioHardwarePropertyDefaultSystemOutputDevice),
                       initial: AudioObjectID(0))
        return (id ?? 0) == 0 ? nil : id
    }

    /// Snapshot of every default the BlackHole recipe would have you change.
    /// `screend` prints this before and after so you can see it did not move.
    struct DefaultsSnapshot: Equatable {
        var output: String?
        var systemOutput: String?
        var input: String?

        static func capture() -> DefaultsSnapshot {
            DefaultsSnapshot(output: CA.defaultOutputDevice.flatMap(CA.name),
                             systemOutput: CA.defaultSystemOutputDevice.flatMap(CA.name),
                             input: CA.defaultInputDevice.flatMap(CA.name))
        }

        var description: String {
            """
            output        : \(output ?? "-")
            system output : \(systemOutput ?? "-")
            input         : \(input ?? "-")
            """
        }
    }
}

func osStatusMessage(_ status: OSStatus) -> String {
    let chars = [
        UInt8((UInt32(bitPattern: status) >> 24) & 0xff),
        UInt8((UInt32(bitPattern: status) >> 16) & 0xff),
        UInt8((UInt32(bitPattern: status) >> 8) & 0xff),
        UInt8(UInt32(bitPattern: status) & 0xff),
    ]
    let printable = chars.allSatisfy { $0 >= 0x20 && $0 < 0x7f }
    let fourCC = printable ? " '\(String(decoding: chars, as: UTF8.self))'" : ""
    return "\(status)\(fourCC)"
}
