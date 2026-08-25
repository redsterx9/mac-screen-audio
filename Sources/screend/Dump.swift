import Foundation
import CoreAudio
import AudioToolbox

/// Prints the raw input stream layout of a device. Diagnostic aid for when a virtual
/// device reports channels it does not actually deliver.
func dumpInputStreams(of device: AudioObjectID) {
    let streams = CA.objectIDs(device, CA.addr(kAudioDevicePropertyStreams,
                                               scope: kAudioObjectPropertyScopeInput))
    print("input streams: \(streams.count)")
    for (index, stream) in streams.enumerated() {
        guard var format = CA.value(stream,
                                    CA.addr(kAudioStreamPropertyVirtualFormat),
                                    initial: AudioStreamBasicDescription()) else { continue }
        let flags = format.mFormatFlags
        let interleaved = (flags & kAudioFormatFlagIsNonInterleaved) == 0
        print("""
          [\(index)] \(Int(format.mSampleRate))Hz \(format.mChannelsPerFrame)ch \
        \(format.mBitsPerChannel)bit \(interleaved ? "interleaved" : "non-interleaved") \
        flags=0x\(String(flags, radix: 16))
        """)
        _ = format
    }
}
