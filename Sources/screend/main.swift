import Foundation
import CoreAudio
import ScreendCore

let kDeviceUID = "io.github.redsterx9.screend.system-audio"
let kDefaultDeviceName = "Screen Recording Audio"
let kAgentLabel = "io.github.redsterx9.screend"
let kAppDeviceUID = "io.github.redsterx9.screend.app-capture"

let usage = """
screend — record your Mac's own audio with the built-in screen recorder

  screend on [--mic [deviceUID]] [--name <name>]
        Create the virtual input device and stay resident (Ctrl-C to stop).
        --mic folds your microphone into the same device so narration is captured too.

  screend off        Remove a device left behind by an earlier run
  screend status     Show state and confirm your audio defaults are untouched
  screend check      Measure, per channel, whether audio is actually arriving
  screend monitor    Live L/R level meter
  screend list       List input and output devices with their UIDs
  screend permission Check or request the Screen & System Audio Recording permission

  screend apps             List apps Core Audio can tap
  screend daw --app <app> [--with <deviceUID>]
                           Expose one app's audio as a live input device for a DAW,
                           so you can run it through plugins in real time.
                           --with keeps your interface's inputs in the same device.

  screend install [--mic]   Start automatically at login
  screend uninstall         Remove the login agent
  screend version           Print the version

screend never changes your default output device, default input device,
or audio interface configuration.
"""

setvbuf(stdout, nil, _IOLBF, 0)

let cli = Arguments(Array(CommandLine.arguments.dropFirst()))

/// `--mic` alone means "the current default input"; `--mic <uid>` picks a specific device.
/// Returns nil only when `--mic` was asked for and no input device exists at all.
func requestedMicrophoneUID() -> String?? {
    let mic = cli.optional("--mic")
    guard mic.present else { return .some(nil) }
    if let explicit = mic.value { return .some(explicit) }
    guard let uid = CA.defaultInputDevice.flatMap(CA.uid) else { return nil }
    return .some(uid)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

switch cli.command {

case "version", "--version", "-v":
    print("screend \(Screend.version)")


case "list":
    for (title, scope) in [("Input devices:", kAudioObjectPropertyScopeInput),
                           ("Output devices:", kAudioObjectPropertyScopeOutput)] {
        print(title)
        for id in CA.allDevices {
            let channels = CA.channelCount(of: id, scope: scope)
            guard channels > 0 else { continue }
            print("  \(CA.name(of: id) ?? "?")  [\(channels)ch, \(Int(CA.sampleRate(of: id)))Hz]")
            print("    UID: \(CA.uid(of: id) ?? "?")")
        }
    }

case "status":
    print(CA.DefaultsSnapshot.capture().description)
    if let device = CA.device(forUID: kDeviceUID) {
        let channels = CA.channelCount(of: device, scope: kAudioObjectPropertyScopeInput)
        print("\nscreend device: on — \(CA.name(of: device) ?? kDefaultDeviceName) [\(channels)ch]"
              + (channels > 2 ? " (microphone included)" : ""))
    } else {
        print("\nscreend device: off")
    }
    print("Login agent:    \(LaunchAgent.statusDescription)")
    print("Screen & System Audio Recording: \(ScreenRecordingPermission.summary)")
    if !ScreenRecordingPermission.isGranted {
        print("\n\(ScreenRecordingPermission.howToFix)")
    }

case "off":
    print(SystemAudioDevice.destroyLeftover(uid: kDeviceUID)
          ? "Device removed." : "Nothing to remove.")

case "check":
    guard let device = CA.device(forUID: kDeviceUID) else {
        fail("device is off — run `screend on` first")
    }
    let channels = CA.channelCount(of: device, scope: kAudioObjectPropertyScopeInput)
    let hasMic = channels > 2
    let meter = ChannelMeter(deviceID: device, channelCount: channels)
    do { try meter.start() } catch { fail("\(error)") }

    Thread.sleep(forTimeInterval: 0.5)
    meter.resetPeaks()
    Thread.sleep(forTimeInterval: 1.0)
    let idle = meter.channelPeaks

    print("Playing a test sound...")
    meter.resetPeaks()
    let player = Process()
    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    player.arguments = ["/System/Library/Sounds/Submarine.aiff"]
    try? player.run()
    player.waitUntilExit()
    Thread.sleep(forTimeInterval: 0.2)
    let active = meter.channelPeaks
    meter.stop()

    // With a mic mixed in it takes channel 1 and the system audio pair follows it.
    let systemChannels = hasMic ? Array(1..<channels) : Array(0..<channels)
    print("")
    for c in 0..<channels {
        let label = hasMic && c == 0 ? "mic   " : "system"
        print("  ch\(c + 1) \(label)  idle \(dbString(idle[c]))   playing \(dbString(active[c]))")
    }

    let systemHeard = systemChannels.contains { active[$0] - idle[$0] > 0.01 }
    if systemHeard {
        print("\n✅ System audio is reaching the device. Select it in the screen recorder.")
    } else if !ScreenRecordingPermission.isGranted {
        // The overwhelmingly common cause. A tap without this permission is created
        // successfully and returns buffers full of silence, with no error anywhere.
        print("""

        ❌ Silence on every channel, because the Screen & System Audio Recording
           permission is missing. A Core Audio tap without it reports no error —
           it just hands back silence.
        \(ScreenRecordingPermission.howToFix)
        """)
    } else {
        print("\n❌ System channels did not react to playback.")
    }

    if hasMic {
        if active[0] < 0.001 {
            print("⚠️  The microphone channel is silent.")
            print("   Check System Settings → Privacy & Security → Microphone.")
        } else if active[0] > 0.95 {
            print("⚠️  The microphone is clipping (\(dbString(active[0]))).")
            print("   Lower the input volume in System Settings → Sound → Input.")
        }
    }
    if !systemHeard { exit(1) }

case "on":
    let name = cli.value(for: "--name", default: kDefaultDeviceName)
    guard let micUID = requestedMicrophoneUID() else { fail("no microphone device found") }
    let clockUID = cli.value(for: "--clock")
    let tapDeviceUID = cli.value(for: "--tap-device")

    _ = SystemAudioDevice.destroyLeftover(uid: kDeviceUID)

    let before = CA.DefaultsSnapshot.capture()
    let device = SystemAudioDevice(deviceName: name, deviceUID: kDeviceUID)
    do {
        try device.create(excludingProcesses: [getpid()],
                          clockDeviceUID: clockUID,
                          microphoneUID: micUID,
                          tapDeviceUID: tapDeviceUID)
    } catch {
        device.destroy()
        fail("\(error)")
    }

    let after = CA.DefaultsSnapshot.capture()
    let channels = CA.channelCount(of: device.aggregateDeviceID, scope: kAudioObjectPropertyScopeInput)

    print("""
    ✅ Ready: \(name)  [\(channels)ch\(micUID != nil ? ", microphone included" : "")]

    Press Cmd+Shift+5 → Options → Microphone → "\(name)", then record.

    Audio defaults (unchanged):
    \(after.description)
    """)
    if before != after {
        print("\n⚠️  Your audio defaults changed. They were:\n\(before.description)")
    }
    if !ScreenRecordingPermission.isGranted {
        print("""

        ⚠️  Screen & System Audio Recording permission is missing.
           The device exists but will capture silence until it is granted.
        \(ScreenRecordingPermission.howToFix)
        """)
    }

    print("\nCtrl-C removes the device and exits.")

    // A process tap dies with the process that created it, so screend has to stay resident.
    signalHandlerDevice = device
    let cleanup: @convention(c) (Int32) -> Void = { _ in
        signalHandlerDevice?.destroy()
        exit(0)
    }
    signal(SIGINT, cleanup)
    signal(SIGTERM, cleanup)
    device.watchForClockDeviceRemoval()
    RunLoop.main.run()

case "permission":
    if ScreenRecordingPermission.isGranted {
        print("Screen & System Audio Recording: already granted.")
    } else {
        print("Requesting Screen & System Audio Recording permission...")
        ScreenRecordingPermission.request()
        print(ScreenRecordingPermission.isGranted
              ? "Granted."
              : "Still missing.\n\n\(ScreenRecordingPermission.howToFix)")
    }

case "apps":
    let processes = AudioProcess.all
        .filter { $0.bundleID != nil }
        .sorted { ($0.isPlaying ? 0 : 1, $0.name.lowercased()) < ($1.isPlaying ? 0 : 1, $1.name.lowercased()) }
    print("Apps Core Audio knows about (▶ = playing right now):")
    for process in processes {
        print("  \(process.isPlaying ? "▶" : " ") \(process.name)")
        print("      \(process.bundleID ?? "?")   pid \(process.pid)")
    }

case "daw":
    // Expose one app's audio as a live input device, so a DAW can put plugins on it.
    guard let query = cli.value(for: "--app") ?? cli.value(for: "--pid") else {
        fail("which app? e.g. screend daw --app Spotify   (see `screend apps`)")
    }
    let matched = AudioProcess.matching(query)
    guard !matched.isEmpty else {
        fail("no audio process matches \"\(query)\" — run `screend apps` to see the list")
    }
    let appName = matched.first(where: { $0.isPlaying })?.name ?? matched[0].name
    let deviceName = cli.value(for: "--name", default: "\(appName) Capture")

    // --with keeps your interface's inputs in the same device, so a guitar or mic still
    // reaches the DAW alongside the tapped app instead of being displaced by it.
    let extraInputUID = cli.value(for: "--with")
    let extraInputChannels = extraInputUID
        .flatMap(CA.device(forUID:))
        .map { CA.channelCount(of: $0, scope: kAudioObjectPropertyScopeInput) } ?? 0

    _ = SystemAudioDevice.destroyLeftover(uid: kAppDeviceUID)

    let dawBefore = CA.DefaultsSnapshot.capture()
    let dawDevice = SystemAudioDevice(deviceName: deviceName, deviceUID: kAppDeviceUID)
    do {
        try dawDevice.create(clockDeviceUID: cli.value(for: "--clock"),
                             microphoneUID: extraInputUID,
                             includingProcesses: matched.map(\.objectID))
    } catch {
        dawDevice.destroy()
        fail("\(error)")
    }

    let dawChannels = CA.channelCount(of: dawDevice.aggregateDeviceID,
                                      scope: kAudioObjectPropertyScopeInput)
    let appChannelStart = extraInputChannels + 1

    print("""
    ✅ \(deviceName)  [\(dawChannels)ch]
       Tapping \(matched.count) process\(matched.count == 1 ? "" : "es") of \(appName), and nothing else.
       Your DAW's own output is not in the tap, so there is no feedback loop.
    """)

    if extraInputChannels > 0, let extraInputUID {
        let extraName = CA.device(forUID: extraInputUID).flatMap(CA.name) ?? extraInputUID
        print("""
          Channels 1-\(extraInputChannels)   \(extraName)
          Channels \(appChannelStart)-\(appChannelStart + 1)   \(appName)
        """)
    } else {
        print("""
          Channels 1-2   \(appName)

        ⚠️  This device has no hardware inputs, so selecting it in your DAW replaces them —
           no guitar, no mic. To keep both, pass your interface:
             screend daw --app \(query) --with <device UID>     (see `screend list`)
        """)
    }

    print("""
    In Logic Pro:
      1. Settings → Audio → Devices → Input Device → "\(deviceName)"
         Leave Output Device alone. Logic takes input and output from separate devices.
      2. New stereo audio track, Input \(appChannelStart)-\(appChannelStart + 1).
      3. Arm it (R) and turn on Input Monitoring (I).
      4. Drop plugins on the track. They process \(appName) live.

    Audio defaults (unchanged):
    \(CA.DefaultsSnapshot.capture().description)
    """)
    if dawBefore != CA.DefaultsSnapshot.capture() {
        print("\n⚠️  Your audio defaults changed. They were:\n\(dawBefore.description)")
    }
    if !ScreenRecordingPermission.isGranted {
        print("""

        ⚠️  Screen & System Audio Recording permission is missing — this will be silent.
        \(ScreenRecordingPermission.howToFix)
        """)
    }
    print("""

    Check it is working:  screend monitor --uid \(kAppDeviceUID)
    Ctrl-C removes the device and exits.
    """)

    signalHandlerDevice = dawDevice
    let dawCleanup: @convention(c) (Int32) -> Void = { _ in
        signalHandlerDevice?.destroy()
        exit(0)
    }
    signal(SIGINT, dawCleanup)
    signal(SIGTERM, dawCleanup)
    RunLoop.main.run()

case "peak":
    // Diagnostic: report the highest level seen on each channel over a fixed window.
    guard let device = CA.device(forUID: cli.value(for: "--uid", default: kDeviceUID)) else {
        fail("device is off")
    }
    let peakChannels = CA.channelCount(of: device, scope: kAudioObjectPropertyScopeInput)
    let peakMeter = ChannelMeter(deviceID: device, channelCount: peakChannels)
    do { try peakMeter.start() } catch { fail("\(error)") }
    Thread.sleep(forTimeInterval: 0.3)
    peakMeter.resetPeaks()
    Thread.sleep(forTimeInterval: cli.doubleValue(for: "--seconds", default: 3))
    let observed = peakMeter.channelPeaks
    peakMeter.stop()
    print(observed.map(dbString).joined(separator: "  "))

case "monitor":
    guard let device = CA.device(forUID: cli.value(for: "--uid", default: kDeviceUID)) else {
        fail("device is off — run `screend on` first")
    }
    let monitorChannels = CA.channelCount(of: device, scope: kAudioObjectPropertyScopeInput)
    let monitor = ChannelMeter(deviceID: device, channelCount: monitorChannels)
    do { try monitor.start() } catch { fail("\(error)") }

    print("Live levels — start playback in your DAW or browser. Ctrl-C to stop.\n")
    signal(SIGINT) { _ in print("\n"); exit(0) }

    while true {
        Thread.sleep(forTimeInterval: 0.15)
        let peaks = monitor.channelPeaks
        monitor.resetPeaks()
        let bars = peaks.enumerated().map { index, peak -> String in
            let label = monitorChannels > 2 && index == 0 ? "MIC" : (index % 2 == 0 ? " L " : " R ")
            return "\(label) |\(levelBar(peak))| \(dbString(peak))"
        }
        print("\u{1B}[2K" + bars.joined(separator: "   "), terminator: "\r")
        fflush(stdout)
    }

case "install":
    guard let micUID = requestedMicrophoneUID() else { fail("no microphone device found") }
    do {
        let path = try LaunchAgent.install(withMicrophone: micUID != nil)
        print("""
        ✅ Login agent installed: \(path)
        "\(kDefaultDeviceName)" will be available every time you log in.
        Remove it with: screend uninstall
        """)
    } catch { fail("\(error)") }

case "uninstall":
    do {
        try LaunchAgent.uninstall()
        _ = SystemAudioDevice.destroyLeftover(uid: kDeviceUID)
        print("Login agent removed and device cleaned up.")
    } catch { fail("\(error)") }

case "tone":
    // Diagnostic: send a test tone to a specific output device.
    let toneDevice = cli.value(for: "--device",
                               default: CA.builtInOutputDevice.flatMap(CA.uid) ?? "")
    var toneChannels: Set<Int> = [0, 1]
    if cli.has("--left") { toneChannels = [0] }
    if cli.has("--right") { toneChannels = [1] }
    do {
        try ToneGenerator.play(deviceUID: toneDevice,
                               frequency: cli.doubleValue(for: "--frequency", default: 1000),
                               seconds: cli.doubleValue(for: "--seconds", default: 3),
                               channels: toneChannels,
                               amplitude: cli.floatValue(for: "--amp", default: 0.25))
    } catch { fail("\(error)") }

case "dump":
    guard let device = CA.device(forUID: kDeviceUID) else { fail("device is off") }
    print("Input channels: \(CA.channelCount(of: device, scope: kAudioObjectPropertyScopeInput))")
    dumpInputStreams(of: device)

default:
    print(usage)
}
