import Foundation
import CoreAudio
import ScreendCore
import AudioToolbox

enum ScreendError: Error, CustomStringConvertible {
    case coreAudio(String, OSStatus)
    case message(String)

    var description: String {
        switch self {
        case .coreAudio(let what, let status): return "\(what) failed (\(osStatusMessage(status)))"
        case .message(let text): return text
        }
    }
}

/// Creates a *public* input device whose audio is a mirrored copy of everything the Mac is
/// playing, using a Core Audio process tap.
///
/// The point of doing it this way: a tap is a passive copy. It does not become the destination
/// for anything, so the default output device, the default system output device, and every
/// music app's device selection are all left exactly where they were. Nothing to restore later.
final class SystemAudioDevice {

    let deviceName: String
    let deviceUID: String

    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var tapUUID = UUID()

    init(deviceName: String, deviceUID: String) {
        self.deviceName = deviceName
        self.deviceUID = deviceUID
    }

    var aggregateDeviceID: AudioObjectID { aggregateID }

    // MARK: - Lifecycle

    func create(excludingProcesses excluded: [pid_t] = [],
                clockDeviceUID: String? = nil,
                microphoneUID: String? = nil) throws {
        try createTap(excluding: excluded)

        // The aggregate needs a real device to take its clock from — a tap on its own has no
        // timebase and the device refuses to start. The clock device is referenced, not
        // reconfigured: it stays the system default, stays available to every other app, and
        // screend never writes to it. Drift compensation absorbs any rate mismatch.
        // When a microphone is mixed in it also supplies the clock, which keeps the audio
        // interface out of the aggregate entirely.
        // When a microphone is mixed in it also supplies the clock. Otherwise the built-in
        // speakers do — never the audio interface, which stays out of the aggregate entirely.
        guard let clockUID = clockDeviceUID
                ?? microphoneUID
                ?? CA.builtInOutputDevice.flatMap(CA.uid)
                ?? CA.defaultOutputDevice.flatMap(CA.uid) else {
            throw ScreendError.message("no output device available to clock the aggregate")
        }
        clockUID_ = clockUID

        microphoneUID_ = microphoneUID
        aggregateID = try createAggregate(clockDeviceUID: clockUID, microphoneUID: microphoneUID)
        guard CA.channelCount(of: aggregateID, scope: kAudioObjectPropertyScopeInput) > 0 else {
            throw ScreendError.message("virtual device was created but exposes no input channels")
        }
    }

    private(set) var clockUID_: String?
    private(set) var microphoneUID_: String?

    private func createTap(excluding excluded: [pid_t]) throws {
        let objectIDs = excluded.compactMap(Self.audioObjectID(forPID:))
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: objectIDs)
        description.name = "\(deviceName) Tap"
        description.uuid = tapUUID
        // Public: the tap has to be readable by the *recorder* process, not just by screend.
        description.isPrivate = false
        // Unmuted: the audio keeps playing out of the speakers/interface while it is copied.
        description.muteBehavior = CATapMuteBehavior.unmuted

        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &id)
        guard status == noErr, id != AudioObjectID(kAudioObjectUnknown) else {
            throw ScreendError.coreAudio("creating the system audio tap", status)
        }
        tapID = id
    }

    private func createAggregate(clockDeviceUID clockUID: String,
                                 microphoneUID: String?) throws -> AudioObjectID {
        var subDevices: [[String: Any]] = [[
            kAudioSubDeviceUIDKey: clockUID,
            kAudioSubDeviceDriftCompensationKey: 1,
        ]]
        if let microphoneUID, microphoneUID != clockUID {
            subDevices.append([
                kAudioSubDeviceUIDKey: microphoneUID,
                kAudioSubDeviceDriftCompensationKey: 1,
            ])
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: deviceName,
            kAudioAggregateDeviceUIDKey: deviceUID,
            // Public so Cmd+Shift+5, QuickTime and screencapture can see it in the mic list.
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: clockUID,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: 1,
                kAudioSubTapUIDKey: tapUUID.uuidString,
            ]],
        ]

        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr, id != AudioObjectID(kAudioObjectUnknown) else {
            throw ScreendError.coreAudio("creating the virtual input device", status)
        }
        return id
    }

    /// Tears everything back down. Safe to call twice.
    func destroy() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Rebuilds the aggregate if its clock device goes away — an interface being unplugged
    /// would otherwise leave the virtual device present but dead.
    func watchForClockDeviceRemoval() {
        var address = CA.addr(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self, let clockUID = self.clockUID_ else { return }
            guard CA.device(forUID: clockUID) == nil else { return }
            let mic = self.microphoneUID_
            self.destroy()
            try? self.create(excludingProcesses: [getpid()], microphoneUID: mic)
        }
    }

    /// Removes a device left behind by an earlier run that did not exit cleanly.
    static func destroyLeftover(uid: String) -> Bool {
        guard let id = CA.device(forUID: uid) else { return false }
        return AudioHardwareDestroyAggregateDevice(id) == noErr
    }

    private static func audioObjectID(forPID pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var address = CA.addr(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid,
                                                &size, &id)
        return status == noErr && id != AudioObjectID(kAudioObjectUnknown) ? id : nil
    }
}
