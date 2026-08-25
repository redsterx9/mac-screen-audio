# screend

**Record your Mac's own audio with the built-in screen recorder — without touching a single audio setting.**

[![build](https://github.com/redsterx9/mac-screen-audio/actions/workflows/build.yml/badge.svg)](https://github.com/redsterx9/mac-screen-audio/actions/workflows/build.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![platform](https://img.shields.io/badge/macOS-14.2%2B-lightgrey)

[한국어 문서](README.ko.md)

---

macOS screen recording (`Cmd+Shift+5`, QuickTime) can capture a microphone, but not the sound
your Mac is actually playing. No YouTube audio, no game audio, no call audio, no DAW output.

`screend` fixes that by exposing a **Core Audio process tap** as a normal input device. Pick it
in the recorder's Microphone menu and your system audio lands in the recording, in stereo.

```bash
brew install redsterx9/tap/screend
brew services start screend
```

Then: `Cmd+Shift+5` → **Options** → **Microphone** → **"Screen Recording Audio"** → record.
macOS remembers the choice.

<details>
<summary>Without Homebrew</summary>

```bash
git clone https://github.com/redsterx9/mac-screen-audio
cd mac-screen-audio
./install.sh
```

`install.sh` builds, copies the binary to `~/.local/bin`, and registers its own login agent.
</details>

## It does not touch your audio setup

This is the whole point. The usual BlackHole recipe breaks things not because of BlackHole
itself, but because of the step that says *"create a Multi-Output Device and make it your system
output."* The moment your output device changes, your interface routing is wrong, and you get to
put it back every time you want to do actual work.

A process tap is a passive copy of audio that is already playing. So:

|                                   | screend | BlackHole + Multi-Output |
| --------------------------------- | ------- | ------------------------ |
| Changes your default output device | No      | **Yes**                  |
| Changes your default input device  | No      | No                       |
| Touches your audio interface       | No      | **Yes**                  |
| Installs a driver                  | No      | **Yes**                  |
| Needs an admin password            | No      | **Yes**                  |
| You still hear the audio           | Yes     | Yes                      |
| Stereo L/R preserved               | Yes     | Yes                      |

`screend off` removes the device and leaves nothing to undo. `screend status` prints your audio
defaults any time you want to confirm they have not moved.

## Recording a DAW

Yes, this captures Logic Pro, Ableton, or anything else — including when the DAW is playing
through an audio interface and `screend` is not.

The tap is **process-scoped, not device-scoped**. It follows the application, not the output
route. Verified: a tone sent to a non-default output device was captured cleanly.

To confirm on your own rig, run `screend monitor`, then hit play in your DAW and watch the meter.

One thing to know: the tap captures the DAW's **final output**, below the master fader. Pull the
master down and the recording comes down with it. For a real mixdown, bounce from the DAW —
this is for getting reference audio into a screen recording.

## Stereo

Left and right stay separate. Play 1 kHz on the left and 3 kHz on the right, record it, and each
channel carries only its own tone with the opposite channel below −86 dB — roughly **72 dB of
channel separation**. Output is `2 ch, 48000 Hz, Stereo (L R)`.

## Commands

| Command | What it does |
| --- | --- |
| `screend on` | Create the device and stay resident (Ctrl-C to stop) |
| `screend off` | Remove a device left behind by an earlier run |
| `screend status` | Show state and confirm your audio defaults are untouched |
| `screend check` | Measure, per channel, whether audio is actually arriving |
| `screend monitor` | Live L/R level meter |
| `screend list` | List input devices and their UIDs |
| `screend install` / `uninstall` | Register or remove the login agent |
| `screend version` | Print the version |
| `screend tone` | Diagnostic test tone (`--device` `--left` `--right` `--amp`) |

## Adding your microphone

`screend on --mic` (or `./install.sh --mic`) folds your microphone into the same device, so
narration and system audio are captured together.

The built-in recorder accepts exactly **one** input device, so the two arrive **mixed into a
single track** — you cannot rebalance them afterwards. If your mic is hot, `screend check` will
warn you; lower it in System Settings → Sound → Input.

## How it works

`screend on` creates two things:

1. A **process tap** over every application's playback, in stereo. `muteBehavior = .unmuted`, so
   the audio keeps playing out of your speakers or interface exactly as before.
2. An **aggregate device** named "Screen Recording Audio" that exposes the tap as input channels.
   It is public, so `screencapture`, QuickTime and the `Cmd+Shift+5` toolbar all list it.

The aggregate takes its clock from the **built-in speakers**, never from your audio interface —
an interface can be unplugged mid-session, and there is no reason to pull it into the aggregate.

A process tap dies with the process that created it, which is why `screend on` stays resident and
why `screend install` registers it as a login agent.

## Verification

Claims in this README were measured, not assumed:

- **Not a microphone path.** With the speakers at volume 0 — nothing audible in the room — a
  1 kHz tone still recorded at −12.2 dB, identical to the level at volume 75.
- **Stereo separation.** Left-only tone → right channel at −240 dB (digital silence).
  L=1 kHz / R=3 kHz → each channel carries only its own tone, opposite channel below −86 dB.
- **Other output devices are captured.** A tone sent to an output device that was neither the
  system default nor the aggregate's clock was captured at −16.5 dB.
- **`screencapture -G` really honours the device.** An unknown UID errors out; an interface with
  nothing plugged in records −71 dB of silence.
- **44.1 kHz sources are not pitch-shifted.** The aggregate is clocked at 48 kHz, so a 44.1 kHz
  source goes through sample rate conversion. A 44.1 kHz 1 kHz tone recorded at exactly 1 kHz,
  at the same level as a 48 kHz one, with nothing at 918 Hz — the frequency a broken conversion
  would have produced.
- **Defaults unchanged** before, during and after a session.
- Final recording: `2 ch, 48000 Hz, Stereo (L R)`, zero clipped samples.

## Requirements

macOS 14.2 or later (Core Audio process taps), Xcode command line tools.

## Notes

- macOS may prompt for Screen Recording and Microphone permission the first time.
- `screend` never writes to any audio device property. It only reads them, and creates and
  destroys its own tap and aggregate device.

## License

MIT
