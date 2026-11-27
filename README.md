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

The tap is a global process tap rather than a tap on one specific device, so it should follow
the application rather than the output route. Treat that as expected rather than proven: the
measurement that was meant to establish it could not distinguish a tone sent to a second output
device from the same tone falling back to the default, so it is being redone.

Check it on your own rig in ten seconds — run `screend monitor`, hit play in your DAW, and watch
the meter.

One thing to know: the tap captures the DAW's **final output**, below the master fader. Pull the
master down and the recording comes down with it. For a real mixdown, bounce from the DAW —
this is for getting reference audio into a screen recording.

## Running an app's audio through your DAW

Same tap, different destination. Instead of handing it to the screen recorder, hand it to Logic
as a **live input** — then it goes through plugins in real time. Put an EQ on Spotify and sweep
it to find what is sitting at 200 Hz. Put a filter on it and solo a frequency band to hear which
instrument lives there.

```bash
screend apps                                    # find the app
screend daw --app Spotify --with <your-interface-UID>
```

In Logic: Settings → Audio → Devices → **Input Device** → the device screend just made. Leave
**Output Device** alone — Logic takes input and output from separate devices, so your monitoring
path does not move. Make a stereo audio track on the app's channels, arm it, turn on Input
Monitoring, and start adding plugins.

### Why `--with` matters

Without it, the capture device has no hardware inputs, so selecting it in Logic **replaces**
them — no guitar, no mic. Pass `--with <interface UID>` and both live in one device: your
interface on channels 1-N, the app after it. `screend list` prints the UIDs.

### Interfaces that come and go

Pass every interface you use, whether or not it is plugged in right now. screend watches the
device list and rebuilds the aggregate when one appears or disappears, so an interface plugged
in after screend started still joins.

The tapped app is always the **last two channels**, because Core Audio puts sub-devices before
taps. So the app's channel numbers move when an interface comes or goes — two interfaces
present might put it on 7-8, one on 5-6. The line screend prints on each rebuild says where it
landed.

### Keep it running

The device exists only while `screend daw` does, so a terminal window is the wrong place for it
— close the window and the device vanishes from your DAW mid-session. Register it instead:

```bash
screend daw --app Spotify --with <interface> --clock <interface> --install
```

That re-registers the same invocation as a login agent, so the device is there after a reboot
and after a DAW restart. `screend daw --uninstall` removes it.

Passing `--clock <interface>` as well puts your interface's **outputs** in the device too, so
one device covers input and output and the DAW needs a single setting rather than two.

### `--with` takes physical interfaces, and only physical ones

Repeat it per device — `--with A --with B`. Not comma separated: Core Audio device UIDs contain
commas themselves (`...:1,2`).

**An aggregate device cannot go inside another aggregate device.** Core Audio refuses it
silently, so the aggregate you built in Audio MIDI Setup cannot be passed to `--with` — pass the
interfaces it contains instead. screend reads the channel map back off the device it actually
created and tells you when channels went missing, rather than printing the layout it asked for.

### The feedback trap this avoids

A global tap captures *everything the Mac plays*, which includes your DAW's own output. Feed
that into the DAW's input and you have built an infinite feedback loop, at whatever volume your
monitors happen to be at.

So `screend daw` scopes the tap to the named app's processes only. Measured: with a tap scoped
to one process, that process's 1 kHz tone recorded at −17.3 dB while a second process playing
3 kHz to the same output device came through at −90.4 dB. 73 dB of separation — your DAW is not
in the tap.

It tracks helper processes too. Spotify, browsers and other Electron apps play audio from a
helper rather than the process you would name, so screend taps the whole bundle family.

### Identifying instruments

Live plugins are good for sweeping and listening. For actually pulling a mix apart, record the
app into a track first and then use Logic's **Stem Splitter** on the region — it separates
vocals, drums, bass and other, which is a different and much stronger tool than an EQ sweep.
Stem Splitter works on recorded regions, not on a live input, which is why the recording step
comes first.

One honest limit: the tap captures the app's final output, after its own volume. Spotify's
volume slider changes what you capture. Leave it at 100% and set listening level at your
interface.

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
| `screend list` | List input and output devices with their UIDs |
| `screend permission` | Check or request the Screen & System Audio Recording permission |
| `screend apps` | List apps Core Audio can tap |
| `screend daw --app <app>` | Expose one app's audio as a live DAW input |
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
- **`screencapture -G` really honours the device.** An unknown UID errors out; an interface with
  nothing plugged in records −71 dB of silence.
- **44.1 kHz sources are not pitch-shifted.** The aggregate is clocked at 48 kHz, so a 44.1 kHz
  source goes through sample rate conversion. A 44.1 kHz 1 kHz tone recorded at exactly 1 kHz,
  at the same level as a 48 kHz one, with nothing at 918 Hz — the frequency a broken conversion
  would have produced.
- **Defaults unchanged** before, during and after a session.
- Final recording: `2 ch, 48000 Hz, Stereo (L R)`, zero clipped samples.

## Permission

screend needs **Screen & System Audio Recording**. This is not optional and it fails quietly: a
Core Audio tap created without that permission is still created successfully and still delivers
audio buffers — they are simply silent, and no API reports an error.

`screend status` and `screend check` both report the permission explicitly, so silence is never
left unexplained. To grant it:

```bash
screend permission
```

macOS shows its dialog only the first time. After that, flip the switch by hand in
System Settings → Privacy & Security → Screen & System Audio Recording, then restart screend.

## Requirements

macOS 14.2 or later (Core Audio process taps), Xcode command line tools.

## Notes

- macOS may prompt for Screen Recording and Microphone permission the first time.
- `screend` never writes to any audio device property. It only reads them, and creates and
  destroys its own tap and aggregate device.

## License

MIT
