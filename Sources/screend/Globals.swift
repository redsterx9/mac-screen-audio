import Foundation

/// Held so the C signal handler can tear the device down on Ctrl-C.
nonisolated(unsafe) var signalHandlerDevice: SystemAudioDevice?
