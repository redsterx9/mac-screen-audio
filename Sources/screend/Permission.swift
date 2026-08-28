import Foundation
import CoreGraphics
import ScreendCore

/// A Core Audio process tap needs the Screen & System Audio Recording permission. Without it
/// the tap is still created successfully and still delivers buffers — they are just silent.
/// Nothing in the Core Audio API reports this, so screend checks the permission directly and
/// says so, rather than letting people record silence and wonder why.
enum ScreenRecordingPermission {

    /// Does not prompt.
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts once, then tells the user where to finish the job. macOS only shows the dialog
    /// the first time; after that the switch has to be flipped by hand in System Settings.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static let howToFix = """
    Grant it in System Settings → Privacy & Security → Screen & System Audio Recording,
    then restart screend. If screend is not in that list, run: screend permission
    """

    static var summary: String {
        isGranted ? "granted" : "MISSING — screend will record silence"
    }
}
