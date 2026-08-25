import Foundation
import AVFoundation
import CoreAudio

/// Plays a test tone out of a chosen output device, optionally to one channel only.
/// Used by `screend verify` to prove two things that cannot be assumed:
/// that the tap keeps left and right separate, and that it hears apps playing to an audio
/// interface rather than only to the device the aggregate clocks from.
enum ToneGenerator {

    /// - Parameter channels: which output channels get signal — `[0]` left only, `[1]` right
    ///   only, `[0, 1]` both.
    static func play(deviceUID: String,
                     frequency: Double,
                     seconds: Double,
                     channels: Set<Int>,
                     amplitude: Float) throws {
        guard let deviceID = CA.device(forUID: deviceUID) else {
            throw ScreendError.message("출력 장치를 찾지 못했습니다: \(deviceUID)")
        }

        let engine = AVAudioEngine()
        try engine.outputNode.auAudioUnit.setDeviceID(deviceID)

        let sampleRate = CA.sampleRate(of: deviceID) > 0 ? CA.sampleRate(of: deviceID) : 48_000
        let outputChannels = max(1, CA.channelCount(of: deviceID, scope: kAudioObjectPropertyScopeOutput))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                         channels: AVAudioChannelCount(outputChannels))
        else { throw ScreendError.message("오디오 포맷을 만들지 못했습니다.") }

        var phase: Double = 0
        let increment = 2 * Double.pi * frequency / sampleRate

        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase)) * amplitude
                phase += increment
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                for (index, buffer) in buffers.enumerated() {
                    let data = buffer.mData!.assumingMemoryBound(to: Float.self)
                    data[frame] = channels.contains(index) ? sample : 0
                }
            }
            return noErr
        }

        engine.attach(source)
        // Straight to the output node — mainMixerNode would down-mix and destroy the
        // per-channel routing this test exists to check.
        engine.connect(source, to: engine.outputNode, format: format)
        try engine.start()
        Thread.sleep(forTimeInterval: seconds)
        engine.stop()
    }
}
