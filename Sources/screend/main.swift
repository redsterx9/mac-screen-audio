import Foundation
import CoreAudio
import ScreendCore

let kDeviceUID = "io.github.redsterx9.screend.system-audio"
let kDefaultDeviceName = "Screen Recording Audio"
let kAgentLabel = "io.github.redsterx9.screend"

let usage = """
screend — record your Mac's own audio with the built-in screen recorder

  screend on [--mic [deviceUID]] [--name <name>]
        Create the virtual input device and stay resident (Ctrl-C to stop).
        --mic folds your microphone into the same device so narration is captured too.

  screend off        Remove a device left behind by an earlier run
  screend status     Show state and confirm your audio defaults are untouched
  screend check      Measure, per channel, whether audio is actually arriving
  screend monitor    Live L/R level meter
  screend list       List input devices and their UIDs

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
    print("Input devices:")
    for id in CA.allDevices {
        let inputs = CA.channelCount(of: id, scope: kAudioObjectPropertyScopeInput)
        guard inputs > 0 else { continue }
        print("  \(CA.name(of: id) ?? "?")  [\(inputs)ch, \(Int(CA.sampleRate(of: id)))Hz]")
        print("    UID: \(CA.uid(of: id) ?? "?")")
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
    print(systemHeard
          ? "\n✅ System audio is reaching the device. Select it in the screen recorder."
          : "\n❌ System channels did not react to playback.")

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

    _ = SystemAudioDevice.destroyLeftover(uid: kDeviceUID)

    let before = CA.DefaultsSnapshot.capture()
    let device = SystemAudioDevice(deviceName: name, deviceUID: kDeviceUID)
    do {
        try device.create(excludingProcesses: [getpid()], microphoneUID: micUID)
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

case "monitor":
    guard let device = CA.device(forUID: kDeviceUID) else {
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
