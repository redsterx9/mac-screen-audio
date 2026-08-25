import Foundation

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

    static func install(withMicrophone mic: Bool) throws -> String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath().standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ScreendError.message("screend 실행 파일 경로를 찾지 못했습니다: \(executable)")
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

        _ = try? launchctl(["bootout", "gui/\(getuid())/\(kAgentLabel)"])
        try launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        return plistURL.path
    }

    static func uninstall() throws {
        _ = try? launchctl(["bootout", "gui/\(getuid())/\(kAgentLabel)"])
        if isInstalled { try FileManager.default.removeItem(at: plistURL) }
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
            throw ScreendError.message("launchctl \(arguments.joined(separator: " ")) 실패")
        }
        return process.terminationStatus
    }
}
