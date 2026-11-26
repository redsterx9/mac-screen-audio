import Foundation
import CoreAudio
import AppKit
import Darwin
import ScreendCore

/// One application as Core Audio sees it. Used to scope a tap to a single app, which matters
/// for the DAW case: a global tap would also capture the DAW's own output, and feeding that
/// back into the DAW's input is an instant feedback loop.
struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isPlaying: Bool

    var name: String {
        if let app = NSRunningApplication(processIdentifier: pid), let localized = app.localizedName {
            return localized
        }
        // Command line tools have no bundle ID and no NSRunningApplication entry, so fall back
        // to the executable name — otherwise they cannot be named on the command line at all.
        if let executable = Self.executableName(pid: pid) { return executable }
        if let bundleID { return bundleID }
        return "pid \(pid)"
    }

    static func executableName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    /// Matches on app name or bundle ID, case-insensitively, so `--app spotify` is enough.
    func matches(_ query: String) -> Bool {
        let needle = query.lowercased()
        if name.lowercased().contains(needle) { return true }
        if let bundleID, bundleID.lowercased().contains(needle) { return true }
        return false
    }

    static var all: [AudioProcess] {
        CA.objectIDs(AudioObjectID(kAudioObjectSystemObject),
                     CA.addr(kAudioHardwarePropertyProcessObjectList))
            .map { id in
                AudioProcess(
                    objectID: id,
                    pid: CA.value(id, CA.addr(kAudioProcessPropertyPID), initial: pid_t(0)) ?? 0,
                    bundleID: CA.string(id, CA.addr(kAudioProcessPropertyBundleID)),
                    isPlaying: (CA.value(id, CA.addr(kAudioProcessPropertyIsRunningOutput),
                                         initial: UInt32(0)) ?? 0) != 0)
            }
    }

    /// Every process of an app. Spotify, browsers and other Electron apps play audio from a
    /// helper process rather than the one you would name, so tapping only the process whose
    /// name matched would capture nothing.
    static func matching(_ query: String) -> [AudioProcess] {
        let processes = all

        // An explicit pid wins over any name matching.
        if let pid = pid_t(query) {
            return processes.filter { $0.pid == pid }
        }

        let hits = processes.filter { $0.matches(query) }
        guard !hits.isEmpty else { return [] }

        // The shortest matching bundle ID is the app itself; the rest are its helpers,
        // which are named by extending it ("com.spotify.client.helper").
        let bundleIDs = hits.compactMap(\.bundleID)
        guard let base = bundleIDs.min(by: { $0.count < $1.count }) else { return hits }
        let family = processes.filter {
            guard let id = $0.bundleID else { return false }
            return id == base || id.hasPrefix(base + ".")
        }
        return family.isEmpty ? hits : family
    }
}
