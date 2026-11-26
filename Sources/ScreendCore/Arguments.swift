/// Command-line parsing, split out so it can be tested without an audio device attached.
public struct Arguments: Sendable {

    public let command: String
    private let tokens: [String]

    public init(_ argv: [String]) {
        command = argv.first ?? "help"
        tokens = Array(argv.dropFirst())
    }

    public func has(_ flag: String) -> Bool { tokens.contains(flag) }

    /// The token after `flag`, or nil if the flag is absent or is followed by another flag.
    public func value(for flag: String) -> String? {
        guard let i = tokens.firstIndex(of: flag), i + 1 < tokens.count else { return nil }
        let next = tokens[i + 1]
        return next.hasPrefix("--") ? nil : next
    }

    /// Every value given for a repeated flag, e.g. `--with A --with B`. Core Audio device
    /// UIDs contain commas, so a comma separated list is not an option here.
    public func values(for flag: String) -> [String] {
        var found: [String] = []
        for (index, token) in tokens.enumerated() where token == flag {
            guard index + 1 < tokens.count else { continue }
            let next = tokens[index + 1]
            if !next.hasPrefix("--") { found.append(next) }
        }
        return found
    }

    public func value(for flag: String, default fallback: String) -> String {
        value(for: flag) ?? fallback
    }

    public func doubleValue(for flag: String, default fallback: Double) -> Double {
        value(for: flag).flatMap(Double.init) ?? fallback
    }

    public func floatValue(for flag: String, default fallback: Float) -> Float {
        value(for: flag).flatMap(Float.init) ?? fallback
    }

    /// For flags that may stand alone or carry a value, like `--mic` and `--mic <uid>`.
    /// Returns whether the flag was given, and the value if one followed it.
    public func optional(_ flag: String) -> (present: Bool, value: String?) {
        (has(flag), value(for: flag))
    }
}
