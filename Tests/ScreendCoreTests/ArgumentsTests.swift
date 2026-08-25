import Testing
@testable import ScreendCore

@Suite("Arguments")
struct ArgumentsTests {

    @Test("empty argv falls back to help")
    func emptyArgv() {
        #expect(Arguments([]).command == "help")
    }

    @Test("first token is the command")
    func command() {
        #expect(Arguments(["on", "--mic"]).command == "on")
    }

    @Test("a flag's value is the token after it")
    func flagValue() {
        let args = Arguments(["on", "--name", "My Device"])
        #expect(args.value(for: "--name") == "My Device")
    }

    @Test("a flag followed by another flag has no value")
    func flagFollowedByFlag() {
        let args = Arguments(["on", "--mic", "--name", "X"])
        #expect(args.value(for: "--mic") == nil)
        #expect(args.value(for: "--name") == "X")
    }

    @Test("a trailing flag has no value")
    func trailingFlag() {
        #expect(Arguments(["on", "--mic"]).value(for: "--mic") == nil)
    }

    @Test("a missing flag falls back")
    func missingFlag() {
        #expect(Arguments(["on"]).value(for: "--name", default: "Default") == "Default")
    }

    @Test("--mic distinguishes absent, bare and valued")
    func optionalFlag() {
        #expect(Arguments(["on"]).optional("--mic") == (false, nil))
        #expect(Arguments(["on", "--mic"]).optional("--mic") == (true, nil))
        #expect(Arguments(["on", "--mic", "UID"]).optional("--mic") == (true, "UID"))
    }

    @Test("numeric flags parse, and bad input falls back")
    func numericFlags() {
        let args = Arguments(["tone", "--amp", "0.5", "--seconds", "nope"])
        #expect(args.floatValue(for: "--amp", default: 0.25) == 0.5)
        #expect(args.doubleValue(for: "--seconds", default: 3) == 3)
        #expect(args.doubleValue(for: "--missing", default: 7) == 7)
    }
}

@Suite("Levels")
struct LevelsTests {

    @Test("silence prints as -infinity, not a huge number")
    func silence() {
        #expect(dbString(0) == "-∞ dB")
    }

    @Test("full scale is 0 dB")
    func fullScale() {
        #expect(dbString(1.0) == "0.0 dB")
    }

    @Test("half amplitude is about -6 dB")
    func halfScale() {
        #expect(dbString(0.5) == "-6.0 dB")
    }

    @Test("the bar is always the requested width")
    func barWidth() {
        for level in [Float(0), 0.001, 0.5, 1.0] {
            #expect(levelBar(level, width: 40).count == 40)
        }
    }

    @Test("the bar fills with level")
    func barFills() {
        let quiet = levelBar(0.001).filter { $0 == "█" }.count
        let loud = levelBar(1.0).filter { $0 == "█" }.count
        #expect(quiet < loud)
        #expect(loud == 40)
        #expect(levelBar(0).filter { $0 == "█" }.count == 0)
    }

    @Test("printable status codes show their four-character code")
    func fourCC() {
        #expect(osStatusMessage(1936747378).contains("'spkr'"))
        #expect(osStatusMessage(-66628) == "-66628")
    }
}
