# TAKT Run — chapter two proposal (Android running companion)

Filed 2026-07-14. Build after chapter one (desktop v1) ships. See PRODUCT.md
"Chapter two" for the one-paragraph vision.

## What it is

A phone app for running with a beat you control. Not a sequencer on a phone:
a **player plus tempo instrument**. Patterns are prepared in TAKT on the Mac;
on the run you do exactly three things: pick a beat, start it, and push the
tempo around as your pace changes. Every control is operable mid-stride,
one-handed, without reading the screen.

## The bridge from chapter one

- **`.takt` JSON** is the interchange format. Desktop exports it today; the
  phone imports it (file share intent, Drive folder, USB). No sync service
  in R1.
- **TaktCore is the port**, not the problem: the model and timing math are
  ~300 lines of pure functions with golden tests. Port them to Kotlin and run
  the **same JSON fixtures + expected step times** as conformance tests on
  both platforms, so desktop and phone can never drift apart rhythmically.
- **Same baked WAVs** (TAKT-1 kit) ship in the APK.
- Poor-man's mode already works today: desktop exports N minutes of looped
  beat as `.m4a`; drop the file on the phone and repeat it. Chapter two exists
  because tempo control mid-run is the actual product.

## Stack recommendation: native Kotlin

Kotlin + Jetpack Compose, playback via a software mixer feeding `AudioTrack`
(the lookahead scheduler pattern we already use twice, writing mixed PCM
frames ahead of the write head). No NDK/Oboe needed: this is playback, not
finger drumming; 30–60 ms of buffer is inaudible for this use and bulletproof
against underruns.

Rejected alternatives: Kotlin Multiplatform (desktop is Swift; there is
nothing to share but the JSON contract), Flutter/React Native (fights the
audio layer, gains nothing for a two-screen app).

## Run screen (the whole app, R1)

- **BPM giant readout**, the loudest thing on screen (sunlight-readable).
- **Huge − / + buttons** flanking play in the bottom thumb zone (≥ 88 dp),
  ±1 tap, hold to sweep. Optional volume-rocker nudge for gloves.
- **Lap presets**: three configurable tempo chips (e.g. easy 160 / tempo 170 /
  sprint 180). Tap to jump; the beat follows within one step (≤ 120 ms).
- **Pattern picker**: previous/next beat, name spoken via TTS so eyes stay up.
- **Foreground service + MediaSession**: screen off, lock-screen and headphone
  button control, survives Doze.
- Candy colorway by default, Tungsten for night runs (same OKLCH tokens).

## R2: cadence follow

Phones ship step detectors (`TYPE_STEP_DETECTOR`). Measure cadence over a
rolling window; "follow my stride" locks BPM to cadence (or half/double it,
runners' cadence is ~150–190 which is exactly beat range). Hysteresis and
slew-limiting so the beat nudges rather than jitters. This is the killer
feature: the beat becomes a metronome that follows you, or, flipped, a pacer
you chase (set BPM, match your feet to it).

## Roadmap

- **R1**: player + tempo instrument. Library, run screen, presets,
  MediaSession, .takt import, TAKT-1 kit.
- **R2**: cadence follow, TTS callouts, per-run tempo log (what pace you held).
- **R3**: Wear OS tile as remote (tempo from the wrist), maybe interval
  programs (30s sprint / 90s easy alternation as pattern chains).

## Risks, named

- **AudioTrack underruns on aggressive Doze devices** → foreground service +
  generous buffers; test on a low-end device early.
- **Step detector variance across hardware** → cadence smoothing window +
  manual half/double override; never auto-jump more than ±4 BPM/s.
- **Scope creep toward a phone sequencer** → the phone edits nothing in R1.
  Editing stays on the desktop where the grid lives.
