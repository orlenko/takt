# takt

Native macOS rhythm machine. Read SPEC.md (architecture), PRODUCT.md
(principles), DESIGN.md (visual system) before changing anything substantial.

## Build & test

SPM's own sandbox cannot nest inside a sandboxed session, so always pass
`--disable-sandbox`:

- `swift build --disable-sandbox`
- `swift test --disable-sandbox`
- `swift run --disable-sandbox takt` — run the app
- `swift run --disable-sandbox takt-render-kit` — re-bake TAKT-1 kit WAVs into
  `Sources/TaktAudio/Resources/TAKT-1` (only needed when voice DSP changes;
  WAVs are committed)
- `swift run --disable-sandbox takt-bounce` — render seed previews to
  `preview/*.wav` for listening

## Conventions

- `Pattern` collides with QuickDraw's `Pattern` in any file importing
  AVFoundation: qualify as `TaktCore.Pattern` there.
- Timing/choke math lives in one place (`Timing`, `ChokeMath`) and is shared
  by live playback, WAV bounce, and MIDI export. Never fork it.
- The sequencer queue owns an immutable `SequencerState` snapshot; UI edits
  push copies via `Sequencer.update(_:)`. No shared mutable state.
- Review workflow: run the design-skeptic pass before each new phase;
  hostile-eyes agent after each landed milestone.
