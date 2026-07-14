# takt

register: product

## What it is

A macOS (Apple Silicon) desktop rhythm machine: a step sequencer + drum sampler for
sketching, playing, and exporting percussion loops. Not a DAW. The whole app is
"open it, hear a groove in under 60 seconds, push it around until it's yours,
drag the result into your real project."

## Users

One primary user: a developer-musician at a Mac in the evening, desk lamp on,
often with a MIDI pad controller within reach and a DAW open on another screen.
Fluent in software, impatient with modal ceremony, allergic to bloat. Wants an
instrument, not a document editor.

## Tone

Instrument-grade calm. Confident, tactile, quiet chrome around one loud thing
(the pattern grid). Labels are terse and lowercase-mono like silkscreen on
hardware. No marketing voice anywhere in the UI.

## Anti-references

- Neon-on-blue-black "cyberpunk producer" skins (the first reflex for this category).
- Teenage Engineering beige-minimal cosplay (the second reflex).
- Skeuomorphic plastic: fake screws, brushed metal, drop-shadow knobs.
- DAW maximalism: racks, routing matrices, twelve panels of options.

## Strategic principles

1. The grid is the hero. Everything else is furniture and must stay quiet.
2. Color is information, never decoration: hue = voice, brightness = velocity.
3. Time-to-groove beats feature count. Every feature is judged by whether it
   makes the loop more fun to push around.
4. Play first, file second: saving, exporting, and naming never interrupt playback.

## Chapter two (filed 2026-07-14, not in scope for v1)

A running companion: Vlad runs and wants a beat in his ears that he controls,
both prepared ahead (patterns built on the desktop) and adjusted live
(faster/slower laps). Direction to explore when chapter one ships:

- Android app (or watch-first) playing .takt patterns; the JSON document
  format and the portable timing math (TaktCore) are the bridge between
  chapters. Keep both scrupulously platform-agnostic.
- Run controls are not a sequencer UI: huge tempo up/down, tap-to-lap,
  maybe cadence-matched BPM from the accelerometer (beat follows stride).
- Nothing in chapter one may assume AppKit or AVFoundation inside TaktCore.
