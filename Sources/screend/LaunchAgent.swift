import Foundation
import ScreendCore

/// Registers screend as a login agent. Needed because a Core Audio process tap only lives as
/// long as the process that created it — the virtual device disappears the moment screend
/// exits, so something has to keep it resident for Cmd+Shift+5 to find it.
enum LaunchAgent {

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(kAgentLabel).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Homebrew manages its own launchd job rather than using `screend install`, so a
    /// Homebrew user would otherwise be told no agent is installed while one is clearly running.
    static let homebrewLabel = "homebrew.mxcl.screend"

    static func agentPlistExists(label: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
        return FileManager.default.fileExists(atPath: url.path)
    }

    static var statusDescription: String {
        if isInstalled { return "installed (screend install)" }
        if agentPlistExists(label: homebrewLabel) { return "installed (brew services)" }
        if let stale = legacyLabels.first(where: agentPlistExists) {
            return "not installed (stale agent found: \(stale) — run `screend uninstall`)"
        }
        return "not installed"
    }

    static func install(withMicrophone mic: Bool) throws -> String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ScreendError.message("could not resolve the screend executable: \(executable)")
        }

        var arguments = [executable, "on"]
        if mic { arguments.append("--mic") }

        let plist: [String: Any] = [
            "Label": kAgentLabel,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": "/tmp/\(kAgentLabel).log",
            "StandardErrorPath": "/tmp/\(kAgentLabel).log",
        ]

        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                      format: .xml, options: 0)
        try data.write(to: plistURL)

        for label in [kAgentLabel] + Self.legacyLabels {
            _ = try? launchctl(["bootout", "gui/\(getuid())/\(label)"])
        }
        try launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        return plistURL.path
    }

    /// Labels this agent has shipped under. Older installs are cleaned up too, otherwise a
    /// stale agent keeps running an old binary and fights the current one over the device.
    static let legacyLabels = ["com.rheegeon.screend"]

    static func uninstall() throws {
        for label in [kAgentLabel] + legacyLabels {
            _ = try? launchctl(["bootout", "gui/\(getuid())/\(label)"])
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(label).plist")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ScreendError.message("launchctl \(arguments.joined(separator: " ")) failed")
        }
        return process.terminationStatus
    }
}
