import Foundation

/// Formats a linear 0...1 peak as dBFS. Silence prints as -∞ rather than a huge negative number.
public func dbString(_ linear: Float) -> String {
    linear <= 0.00001 ? "-∞ dB" : String(format: "%.1f dB", 20 * log10(linear))
}

/// Renders a peak as a fixed-width bar spanning -60 dBFS to 0 dBFS.
public func levelBar(_ linear: Float, width: Int = 40) -> String {
    let floor: Double = -60
    var filled = 0
    if linear > 0 {
        let db = Double(20 * log10(linear))
        let fraction: Double = (db - floor) / (0 - floor)
        let scaled = Int(fraction * Double(width))
        filled = min(width, max(0, scaled))
    }
    return String(repeating: "█", count: filled) + String(repeating: "·", count: width - filled)
}

/// Renders an OSStatus with its four-character code when the bytes are printable.
public func osStatusMessage(_ status: Int32) -> String {
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
