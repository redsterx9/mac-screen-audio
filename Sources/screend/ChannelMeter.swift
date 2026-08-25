import Foundation
import CoreAudio
import AudioToolbox

/// Per-channel peak meter driven straight off the device's HAL IOProc.
/// `screend check` uses it to show exactly what is arriving on each channel of the
/// virtual device — system audio on one pair, microphone on its own channel.
final class ChannelMeter {

    private let deviceID: AudioObjectID
    private var procID: AudioDeviceIOProcID?
    private var peaks: [Float]
    private let lock = NSLock()

    init(deviceID: AudioObjectID, channelCount: Int) {
        self.deviceID = deviceID
        self.peaks = Array(repeating: 0, count: channelCount)
    }

    var channelPeaks: [Float] {
        lock.lock(); defer { lock.unlock() }
        return peaks
    }

    func resetPeaks() {
        lock.lock(); peaks = peaks.map { _ in 0 }; lock.unlock()
    }

    func start() throws {
        let block: AudioDeviceIOBlock = { [weak self] _, inputData, _, _, _ in
            self?.consume(inputData)
        }
        var id: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&id, deviceID, nil, block)
        guard status == noErr, let id else {
            throw ScreendError.coreAudio("creating the IOProc", status)
        }
        procID = id
        status = AudioDeviceStart(deviceID, id)
        guard status == noErr else {
            throw ScreendError.coreAudio("starting the device", status)
        }
    }

    func stop() {
        guard let procID else { return }
        AudioDeviceStop(deviceID, procID)
        AudioDeviceDestroyIOProcID(deviceID, procID)
        self.procID = nil
    }

    private func consume(_ inputData: UnsafePointer<AudioBufferList>) {
        // AudioBufferList is a variable-length struct; UnsafeMutableAudioBufferListPointer
        // walks it correctly. Taking a pointer to `.mBuffers` instead only ever addresses the
        // first buffer, which silently reads garbage once the device has more than one stream.
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData))

        var channel = 0
        lock.lock()
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / max(channels, 1)
            guard channels > 0, frames > 0, let raw = buffer.mData else {
                channel += channels
                continue
            }
            let samples = raw.assumingMemoryBound(to: Float.self)
            for c in 0..<channels {
                guard channel + c < peaks.count else { continue }
                var localPeak: Float = 0
                for f in 0..<frames {
                    let v = abs(samples[f * channels + c])
                    if v > localPeak { localPeak = v }
                }
                if localPeak > peaks[channel + c] { peaks[channel + c] = localPeak }
            }
            channel += channels
        }
        lock.unlock()
    }
}
