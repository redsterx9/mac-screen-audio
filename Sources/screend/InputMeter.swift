import Foundation
import AudioToolbox
import ScreendCore

/// Reads a device's input and reports peak level. Used by `screend check` to prove the
/// virtual device is actually carrying the Mac's audio before you rely on it for a take.
final class InputMeter {

    private var queue: AudioQueueRef?
    private var peakValue: Float = 0
    private let lock = NSLock()

    var peak: Float {
        lock.lock(); defer { lock.unlock() }
        return peakValue
    }

    func resetPeak() {
        lock.lock(); peakValue = 0; lock.unlock()
    }

    func start(deviceUID: String, sampleRate: Double = 48_000, channels: UInt32 = 2) throws {
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0)

        let callback: AudioQueueInputCallback = { userData, queue, buffer, _, _, _ in
            guard let userData else { return }
            Unmanaged<InputMeter>.fromOpaque(userData).takeUnretainedValue().consume(buffer)
            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }

        var newQueue: AudioQueueRef?
        var status = AudioQueueNewInput(&format, callback,
                                        Unmanaged.passUnretained(self).toOpaque(),
                                        nil, nil, 0, &newQueue)
        guard status == noErr, let newQueue else {
            throw ScreendError.coreAudio("creating the input queue", status)
        }
        queue = newQueue

        var uid = deviceUID as CFString
        status = withUnsafeMutablePointer(to: &uid) {
            AudioQueueSetProperty(newQueue, kAudioQueueProperty_CurrentDevice,
                                  $0, UInt32(MemoryLayout<CFString>.size))
        }
        guard status == noErr else {
            throw ScreendError.coreAudio("selecting the input device", status)
        }

        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(newQueue, 8192, &buffer)
            if let buffer { AudioQueueEnqueueBuffer(newQueue, buffer, 0, nil) }
        }

        status = AudioQueueStart(newQueue, nil)
        guard status == noErr else {
            throw ScreendError.coreAudio("starting the input queue", status)
        }
    }

    func stop() {
        if let queue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
        }
        queue = nil
    }

    private func consume(_ buffer: AudioQueueBufferRef) {
        let count = Int(buffer.pointee.mAudioDataByteSize) / MemoryLayout<Int16>.size
        guard count > 0 else { return }
        let samples = buffer.pointee.mAudioData.bindMemory(to: Int16.self, capacity: count)
        var localPeak: Int32 = 0
        for i in 0..<count {
            let magnitude = Int32(samples[i]).magnitude
            if Int32(magnitude) > localPeak { localPeak = Int32(magnitude) }
        }
        let normalized = Float(localPeak) / Float(Int16.max)
        lock.lock()
        if normalized > peakValue { peakValue = normalized }
        lock.unlock()
    }
}
