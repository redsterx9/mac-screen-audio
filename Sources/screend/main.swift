import Foundation
import CoreAudio

let kDeviceUID = "com.rheegeon.screend.system-audio"
let kDefaultDeviceName = "화면 녹화 사운드"
let kAgentLabel = "com.rheegeon.screend"

let usage = """
screend — 기본 화면 녹화(Cmd+Shift+5)에 맥북 미디어 소리를 넣어주는 도구

  screend on [--mic [장치UID]] [--name <이름>]
        가상 입력 장치를 켜고 대기합니다 (Ctrl-C 로 종료).
        --mic 를 주면 마이크를 같은 장치에 합쳐서 내레이션까지 한 번에 녹음됩니다.

  screend off        남아 있는 장치 정리
  screend status     현재 상태와 오디오 기본 장치 확인
  screend check      장치에 실제로 소리가 들어오는지 채널별로 검사
  screend monitor    실시간 L/R 레벨 미터 (로직 재생 걸어놓고 확인용)
  screend list       입력 장치와 UID 목록

  screend install [--mic]   로그인할 때 자동으로 켜지도록 등록
  screend uninstall         자동 실행 해제

시스템 출력 장치, 시스템 입력 장치, 오디오 인터페이스 설정은 절대 건드리지 않습니다.
"""

setvbuf(stdout, nil, _IOLBF, 0)

let args = Array(CommandLine.arguments.dropFirst())

/// `--mic` on its own means "the current default input"; `--mic <uid>` picks a specific one.
func microphoneUID(from args: [String]) -> String?? {
    guard let i = args.firstIndex(of: "--mic") else { return .some(nil) }
    if i + 1 < args.count, !args[i + 1].hasPrefix("--") { return .some(args[i + 1]) }
    guard let uid = CA.defaultInputDevice.flatMap(CA.uid) else { return nil }
    return .some(uid)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("오류: \(message)\n".data(using: .utf8)!)
    exit(1)
}

switch args.first ?? "help" {

case "list":
    print("입력 장치:")
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
        print("\nscreend 장치: 켜짐 — \(CA.name(of: device) ?? kDefaultDeviceName) [\(channels)ch]"
              + (channels > 2 ? " (마이크 포함)" : ""))
    } else {
        print("\nscreend 장치: 꺼짐")
    }
    print(LaunchAgent.isInstalled ? "자동 실행: 등록됨" : "자동 실행: 등록 안 됨")

case "off":
    print(SystemAudioDevice.destroyLeftover(uid: kDeviceUID)
          ? "장치를 정리했습니다." : "정리할 장치가 없습니다.")

case "check":
    guard let device = CA.device(forUID: kDeviceUID) else {
        fail("장치가 꺼져 있습니다. 먼저 `screend on` 을 실행하세요.")
    }
    let channels = CA.channelCount(of: device, scope: kAudioObjectPropertyScopeInput)
    let hasMic = channels > 2
    let meter = ChannelMeter(deviceID: device, channelCount: channels)
    do { try meter.start() } catch { fail("\(error)") }

    Thread.sleep(forTimeInterval: 0.5)
    meter.resetPeaks()
    Thread.sleep(forTimeInterval: 1.0)
    let idle = meter.channelPeaks

    print("테스트 사운드를 재생하는 중...")
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
        let label = hasMic && c == 0 ? "마이크  " : "시스템  "
        print("  ch\(c + 1) \(label) 대기 \(dbString(idle[c]))   재생 중 \(dbString(active[c]))")
    }

    let systemHeard = systemChannels.contains { active[$0] - idle[$0] > 0.01 }
    print(systemHeard
          ? "\n✅ 시스템 사운드가 들어옵니다. 기본 화면 녹화에서 이 장치를 고르면 됩니다."
          : "\n❌ 재생해도 시스템 채널 레벨이 오르지 않습니다.")

    if hasMic {
        if active[0] < 0.001 {
            print("⚠️  마이크 채널이 무음입니다. 시스템 설정 → 개인정보 보호 및 보안 → 마이크 확인.")
        } else if active[0] > 0.95 {
            print("⚠️  마이크가 너무 큽니다 (\(dbString(active[0]))). 클리핑이 납니다.")
            print("   시스템 설정 → 사운드 → 입력에서 입력 볼륨을 낮추세요.")
        }
    }
    if !systemHeard { exit(1) }

case "on":
    var name = kDefaultDeviceName
    if let i = args.firstIndex(of: "--name"), i + 1 < args.count { name = args[i + 1] }
    guard let micUID = microphoneUID(from: args) else { fail("마이크 장치를 찾지 못했습니다.") }

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
    ✅ 준비됨: \(name)  [\(channels)ch\(micUID != nil ? ", 마이크 포함" : "")]

    Cmd+Shift+5 → 옵션 → 마이크 → "\(name)" 선택 후 녹화하세요.

    오디오 기본 장치 (그대로입니다):
    \(after.description)
    """)
    if before != after {
        print("\n⚠️  기본 장치가 바뀌었습니다. 이전 상태:\n\(before.description)")
    }
    print("\nCtrl-C 로 종료하면 장치를 제거합니다.")

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

case "install":
    guard let micUID = microphoneUID(from: args) else { fail("마이크 장치를 찾지 못했습니다.") }
    do {
        let path = try LaunchAgent.install(withMicrophone: micUID != nil)
        print("""
        ✅ 자동 실행 등록: \(path)
        지금부터 로그인하면 "\(kDefaultDeviceName)" 장치가 항상 준비되어 있습니다.
        해제하려면: screend uninstall
        """)
    } catch { fail("\(error)") }

case "uninstall":
    do {
        try LaunchAgent.uninstall()
        _ = SystemAudioDevice.destroyLeftover(uid: kDeviceUID)
        print("자동 실행을 해제하고 장치를 정리했습니다.")
    } catch { fail("\(error)") }

case "monitor":
    guard let device = CA.device(forUID: kDeviceUID) else {
        fail("장치가 꺼져 있습니다. 먼저 `screend on` 을 실행하세요.")
    }
    let monitorChannels = CA.channelCount(of: device, scope: kAudioObjectPropertyScopeInput)
    let monitor = ChannelMeter(deviceID: device, channelCount: monitorChannels)
    do { try monitor.start() } catch { fail("\(error)") }

    print("실시간 레벨 — 로직에서 재생을 걸어보세요. Ctrl-C 로 종료.\n")
    signal(SIGINT) { _ in print("\n"); exit(0) }

    while true {
        Thread.sleep(forTimeInterval: 0.15)
        let peaks = monitor.channelPeaks
        monitor.resetPeaks()
        let bars = peaks.enumerated().map { index, peak -> String in
            let level = peak <= 0 ? 0 : max(0, min(40, Int((20 * log10(peak) + 60) / 1.5)))
            let label = monitorChannels > 2 && index == 0 ? "MIC" : (index % 2 == 0 ? " L " : " R ")
            return "\(label) |\(String(repeating: "█", count: level))\(String(repeating: "·", count: 40 - level))| \(dbString(peak))"
        }
        print("\u{1B}[2K" + bars.joined(separator: "   "), terminator: "\r")
        fflush(stdout)
    }

case "tone":
    // 진단용: 지정한 출력 장치로 테스트 톤을 보낸다.
    var toneDevice = CA.builtInOutputDevice.flatMap(CA.uid) ?? ""
    if let i = args.firstIndex(of: "--device"), i + 1 < args.count { toneDevice = args[i + 1] }
    var toneChannels: Set<Int> = [0, 1]
    if args.contains("--left") { toneChannels = [0] }
    if args.contains("--right") { toneChannels = [1] }
    var toneAmp: Float = 0.25
    if let i = args.firstIndex(of: "--amp"), i + 1 < args.count { toneAmp = Float(args[i + 1]) ?? 0.25 }
    var toneSeconds = 3.0
    if let i = args.firstIndex(of: "--seconds"), i + 1 < args.count { toneSeconds = Double(args[i + 1]) ?? 3.0 }
    do {
        try ToneGenerator.play(deviceUID: toneDevice, frequency: 1000,
                               seconds: toneSeconds, channels: toneChannels, amplitude: toneAmp)
    } catch { fail("\(error)") }

case "dump":
    guard let device = CA.device(forUID: kDeviceUID) else { fail("장치가 꺼져 있습니다.") }
    print("입력 채널 \(CA.channelCount(of: device, scope: kAudioObjectPropertyScopeInput))")
    dumpInputStreams(of: device)

default:
    print(usage)
}
