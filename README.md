# takt

A native macOS rhythm machine, plus an Android companion for running with a
beat you control.

**TAKT** (macOS) is a drum machine in the classic step-sequencer tradition:
open it, hear a groove in under a minute, push it around until it's yours,
then drag the result into your DAW. **TAKT Run** (Android, in `android/`) is
the other half: it plays the beats you made on the desktop while you run,
with giant tempo controls built for mid-stride use.

## TAKT (macOS)

- 8-voice sample engine with the built-in TAKT-1 kit (synthesized offline,
  baked to WAVs, committed) and a lookahead sequencer scheduled on the audio
  clock.
- 16-step pattern grid: click to toggle, right-click to cycle velocity
  (soft / normal / accent), drag to paint. Hue names the voice, brightness is
  velocity.
- Pattern slots A–H with chaining: duplicate a block, tweak it, loop the
  whole chain in order, or just the slot you're editing.
- Swing (50–75%), per-lane mute/solo, open-hat choke, genre seeds
  (House, Breaks, Hip-Hop, Techno) as starting points.
- Play it live: QWERTY keys `A S D F G H J K`, or a MIDI keyboard via the GM
  drum map (kick 36, snare 38, clap 39, rim 37, hats 42/46, tom 45, cowbell
  56), velocity-sensitive with hot-plug.
- Exports: Standard MIDI File (960 PPQN, swing baked into the ticks), WAV,
  and long m4a "jog mixes" (5–30 minutes of looped beat for a phone).
- Documents are plain JSON `.takt` files (Cmd-S / Cmd-O), small enough to
  sync anywhere; they are also the interchange format with TAKT Run.
- Three colorways: Candy (default), Tungsten, Linen. One design system,
  OKLCH tokens, documented in DESIGN.md.

### Build and run

Requires macOS 14+ and a Swift 6 toolchain (Xcode 16 or newer). No
third-party dependencies.

```sh
swift run takt              # build and launch the app
swift test                  # timing math, model, MIDI bytes, audio bounce tests
swift run takt-bounce       # render the seed patterns to preview/*.wav
swift run takt-render-kit   # re-bake the TAKT-1 kit (only if voice DSP changes)
```

(If you are building inside a sandboxed environment, add
`--disable-sandbox`; see CLAUDE.md.)

## TAKT Run (Android)

A player plus tempo instrument, not a phone sequencer: pick a beat, start
it, and adjust tempo as your pace changes, by ±1 taps, hold-to-sweep, a
draggable BPM readout, or lap presets (easy 160 / tempo 170 / sprint 180).
Playback is a foreground service, so it keeps going with the screen off. It
ships the same TAKT-1 samples and a line-for-line port of the timing math,
and imports the desktop's `.takt` files.

Build and sideload instructions: [android/README-ANDROID.md](android/README-ANDROID.md).

## Repository layout

| path | what |
|---|---|
| `Sources/TaktCore` | model, timing/swing math, seeds, SMF writer. Pure Swift, no Apple frameworks |
| `Sources/TaktAudio` | AVAudioEngine graph, sequencer, offline bounce, baked kit WAVs |
| `Sources/TaktMIDI` | CoreMIDI input |
| `Sources/TaktUI` | SwiftUI shell, NSView pattern grid, colorway themes |
| `Sources/takt` | app entry point |
| `Sources/takt-render-kit` | offline DSP that bakes the TAKT-1 kit |
| `Sources/takt-bounce` | CLI: render seeds to WAV for listening |
| `android/` | TAKT Run (Kotlin + Compose) |
| `SPEC.md`, `PRODUCT.md`, `DESIGN.md` | architecture, product principles, design system |
| `CHAPTER2.md` | the running-companion proposal that became `android/` |

## Design notes

The timing and choke math live in exactly one place per platform and are
shared by live playback, WAV/m4a bounce, and MIDI export, so what you hear is
what you export. The desktop sequencer schedules against the audio clock with
a 120 ms lookahead; the Android engine goes one step further and schedules in
the sample domain (a step fires when the write cursor crosses its frame),
which makes playback gapless and tempo changes land within one 16th note.

Status: v1 under active development. Remaining before v1: session autosave,
drag-out export, and an adversarial review pass.
