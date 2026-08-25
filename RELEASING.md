# Release plan

Where this can realistically go, in the order that gives the most back for the least work.

**Status:** Stages 1 and 2 are done. `brew install redsterx9/tap/screend` works, `brew services`
manages the resident process, and v0.1.1 is tagged and released. Stages 3–6 are still ahead.

## Stage 1 — Homebrew tap ✅ done

A one-line install is the single biggest difference between "interesting repo" and "thing people
actually run". A tap is just a GitHub repo named `homebrew-tap` with a formula in it.

```
brew install redsterx9/tap/screend
brew services start screend
```

Two things this buys beyond convenience:

- **No code signing, no notarization, no Gatekeeper.** Homebrew builds from source on the user's
  machine, so none of the distribution-signing problem in Stage 3 applies yet.
- **`brew services` replaces the hand-rolled login agent.** Homebrew generates and manages the
  launchd plist. `LaunchAgent.swift` can stay for people who clone the repo, but the Homebrew
  path should use `service do` instead of `screend install`.

Live at [redsterx9/homebrew-tap](https://github.com/redsterx9/homebrew-tap). `brew install`,
`brew services start`, `brew upgrade` and `brew audit --strict --online` are all verified on a
clean install. The formula:

```ruby
class Screend < Formula
  desc "Record your Mac's own audio with the built-in screen recorder"
  homepage "https://github.com/redsterx9/mac-screen-audio"
  url "https://github.com/redsterx9/mac-screen-audio/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "..."          # shasum -a 256 on the release tarball
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on macos: :sonoma      # 14.2+ for Core Audio process taps

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/screend"
  end

  service do
    run [opt_bin/"screend", "on"]
    keep_alive true
    log_path var/"log/screend.log"
    error_log_path var/"log/screend.log"
  end

  test do
    assert_match "Input devices:", shell_output("#{bin}/screend list")
  end
end
```

`--disable-sandbox` is needed because SwiftPM's sandbox blocks the linker flags that embed
`Info.plist`, and without that plist macOS has no usage description to show when it prompts.
Confirmed by building the release tarball from scratch.

## Stage 2 — Tag a release ✅ done

The loop, now exercised twice:

1. Bump `Sources/ScreendCore/Version.swift` and the `Info.plist` version keys.
2. `git tag -a vX.Y.Z && git push origin vX.Y.Z`
3. `gh release create vX.Y.Z`
4. `shasum -a 256` the release tarball, update `url` and `sha256` in the formula, push the tap.
5. `brew update && brew upgrade screend && brew services restart screend`

The formula's `test do` block asserts the reported version matches the formula version, so a
forgotten bump fails the audit rather than shipping quietly.

## Stage 3 — Signing and notarization (only if you ship binaries)

This is where BlackHole spends its effort, because it ships a `.pkg`. If screend stays a
build-from-source Homebrew formula, this stage is optional.

If you do want a downloadable binary:

- Apple Developer Program, $99/yr, for a Developer ID Application certificate.
- `codesign --sign "Developer ID Application: ..." --options runtime --timestamp`
- `xcrun notarytool submit --wait`, then `xcrun stapler staple`.

There is a second reason to care about signing even for the Homebrew path. macOS ties permission
grants to code identity. An ad-hoc signed binary — which is what `swift build` produces — gets an
unstable identity, so a permission grant can in principle be lost on every upgrade.

One data point against that being severe: upgrading 0.1.0 → 0.1.1 through Homebrew replaced the
binary and `screend check` kept working with no new prompt. That is not conclusive — permission
here may be attributed to the launching process rather than to the binary — so it still needs a
test on a machine that has never granted the permission.

## Stage 4 — The real adoption lever: a menu bar app

Be honest about the ceiling here. BlackHole spreads because it is invisible: install it once and
it is just a device in a list. screend is a CLI that has to stay resident and is configured with
`launchctl`. That is a much narrower audience.

A small menu bar app — toggle the device, show the L/R meter that already exists in
`ChannelMeter.swift`, one checkbox for the mic — would reach far more people than any amount of
README polish. The whole audio engine is already written and verified; this is a UI shell over
`SystemAudioDevice`.

It also fixes the permission story: an `.app` bundle gets its own TCC identity and its own row in
System Settings, instead of inheriting whichever terminal launched it.

## Stage 5 — Getting people to find it

The hook is "**BlackHole alternative that doesn't change your audio settings**". That is a known,
specific, widely-felt annoyance, and it is what the README leads with.

- GitHub topics: `macos`, `screen-recording`, `system-audio`, `coreaudio`, `audio-capture`,
  `blackhole-alternative`, `screencapture`, `swift`.
- A GIF at the top of the README. Record it with screend itself — the demo *is* the pitch.
- Places where the pain is discussed: r/macapps, r/MacOS, r/edmproduction and r/Logic_Studio
  (the "record my DAW into a screen recording" angle), Hacker News Show HN.
- The verification section is a differentiator. Most tools in this space assert; this one shows
  measurements. Keep it.

## Stage 6 — homebrew-core

Only after traction. homebrew-core requires notability — roughly 75+ stars, or 30+ forks or
watchers — plus stable, tagged versioning. The tap in Stage 1 works indefinitely until then, and
`brew install redsterx9/tap/screend` is barely longer to type.

## Known gaps before calling it 1.0

Closed while preparing v0.1.0:

- ~~No version string.~~ `screend version` / `--version`, kept in step with `Info.plist`.
- ~~No tests.~~ 14 tests over argument parsing and level formatting, run in CI. The audio path
  still needs a real device and is not unit tested.
- ~~Identifiers hardcoded to `com.rheegeon.*`.~~ Now `io.github.redsterx9.screend`. `uninstall`
  and `install` clean up the old label so existing installs migrate.
- ~~Sample rates other than 48 kHz untested.~~ Measured: a 44.1 kHz source records at the right
  pitch, same level as 48 kHz, nothing at the frequency a bad conversion would produce.

Done in v0.1.0/v0.1.1: the tap is live at `redsterx9/homebrew-tap`, `brew install` and
`brew services start` both verified on a clean install, and `brew audit --strict --online`
passes.

Still open:

- Multi-display and external-display recording untested.
- Behaviour when the built-in speakers are absent (Mac mini with nothing attached, headless)
  is untested — the aggregate clock falls back to the default output device, which should work,
  but it has not been on real hardware.
