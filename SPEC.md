# TAKT — software spec (v1)

Native macOS (Apple Silicon) rhythm machine. Swift + SwiftUI + AVAudioEngine +
CoreMIDI, zero third-party dependencies. See PRODUCT.md for principles,
DESIGN.md for the visual system.

## Goals / non-goals (v1)

Goals: open → hear a groove in under 60 seconds; edit a 16-step pattern with
velocity and swing; jam over it from QWERTY or a MIDI keyboard; export the loop
as WAV or MIDI (including drag-out); never lose work.

Shipped ahead of plan: pattern slots A–H with chaining (loop the whole chain
in order, or just the slot being edited; `SequencerState.playOrder` already
supports arbitrary orders like A-A-B); style kits (Nine-Oh, Dust) sharing
the TAKT-1 voice roles; cued pattern switching in the hardware tradition
(selecting a slot while playing shows it for editing immediately and takes
over playback at the pattern boundary; content edits stay immediate,
structure changes land on the bar); song mode (a SONG row of slot×repeat
entries — `A×4 B×2 A×4 C×1` — as a third loop mode next to chain/slot,
persisted in the `.takt` document's `song` field; exports and TAKT Run
follow the arrangement because everything downstream already consumes
`playOrder`); time signatures (per-slot meter 2/4–7/4 as a value chip in the
pattern bar; `stepCount` = beats × 4 sixteenths, so the engine, choke, bounce,
and Android player were already meter-agnostic — the grid draws N flexing
columns and the SMF writer emits time-signature metas at meter changes;
mixed-meter chains and songs work); and the sacred playing surface (song
edits while the song plays land at the pattern boundary and resume at the
entry that was sounding — `Sequencer.cueOrder(startAt:)` — never restarting
the arrangement).

The editing surface follows one interaction grammar (adopted after a UX
review; see the design artifact): containers (slots, song entries, lanes) get
right-click menus with exactly three verbs — Duplicate, Clear (empty the
content), Remove (take the container out) — plus Move Left/Right where order
matters, and menu verbs never move selection, cue, or playback; values
(velocity, BPM, swing, repeats) are manipulated directly and never grow
menus. Destructive chips name their object ("clear A", "+ A", "clear song").
Loop mode lives on the transport next to play. A snapshot undo ring (⌘Z/⇧⌘Z,
composite of project + loop mode + seed label, gesture-coalesced) backs every
mutation; undo never cues and never stops playback. File › New completes the
document verb ladder.

Non-goals in v1 (deferred, the model must not preclude them): 32-step UI,
probability/ratchets, polymeter, user sample import, MIDI learn mode, MIDI
clock sync, per-step automation. The model stays agnostic (`stepCount`,
`midiOverrides`, `playOrder`), the v1 UI does not.

## Build system

Swift Package Manager, `swift-tools-version: 6.0`, Swift language mode v5 (the
audio layer talks to pre-Sendable AVFoundation APIs; strict concurrency
adoption is a later chore, not a v1 fight). Minimum platform `macOS 14`.

- `swift build && swift run takt` for development (SPM executable presents a
  regular SwiftUI window; activation policy is set programmatically).
- `make app` assembles `Takt.app` (bundle skeleton + Info.plist + binary +
  resources) for Dock-grade use. No sandbox in v1 dev builds.

Targets:

| target | kind | depends on | purpose |
|---|---|---|---|
| `TaktCore` | library | — | model, timing math, seeds, SMF writer. Pure Swift, fully testable. |
| `TaktAudio` | library | TaktCore | AVAudioEngine playback, sequencer scheduling, offline bounce |
| `TaktMIDI` | library | TaktCore | CoreMIDI input, mapping, learn mode |
| `takt` | executable | all above | SwiftUI app |
| `takt-render-kit` | executable | TaktCore | offline DSP that bakes the TAKT-1 kit WAVs (dev tool) |
| `TaktCoreTests`, `TaktAudioTests` | tests | | |

## Data model (TaktCore, all Codable + Equatable)

```swift
struct Voice     { id, name, hueDegrees, sampleFile, gmNote, chokeGroup: Int? }
struct Kit       { id, name, voices: [Voice] }          // kit.json in resources
struct Step      { velocity: UInt8 }                    // 0 = off; UI writes 0/54/96/127
struct Track     { voiceID, steps: [Step], isMuted, isSoloed, level: Float = 1 }
struct Pattern   { name, stepCount: Int, tracks: [Track] }   // v1 UI always 16
struct Project   { schemaVersion, kitID, tempoBPM: Double, swingPercent: Double (50...75), patterns: [Pattern], currentPatternIndex, midiOverrides: [Int: VoiceID] }
```

Velocity is stored in MIDI's native 0–127; the UI quantizes to three levels
(soft 54, normal 96, accent 127). MIDI input records the real value. This is
the domain unit, not speculative generality.

`patterns` is an array from day one (chains are v1.1), but v1 UI shows exactly
one pattern.

GM drum map defaults: kick 36, snare 38, clap 39, rim 37, closed hat 42, open
hat 46, low tom 45, cowbell 56. Choke: closed hat and open hat share group 1.

### Timing math (pure functions, golden-tested)

```swift
// start of step k within the loop, seconds
stepTime(k, tempo, swing):
  s16  = 60 / tempo / 4
  pair = 2 * s16
  base = floor(k/2) * pair
  return k.isMultiple(of: 2) ? base : base + pair * (swing/100)
loopDuration = stepCount/2 * pair
```

Swing 50% = straight, 66.7% = triplet feel, capped at 75%. One function feeds
the live scheduler, WAV bounce, and MIDI export, so all three always agree.

## Audio engine (TaktAudio)

Graph: per-voice pool of 3 `AVAudioPlayerNode`s (round-robin, so fast
retriggers overlap instead of queueing) → per-voice `AVAudioMixerNode` (level,
future pan) → main mixer (0.8) → peak limiter AU
(`kAudioUnitSubType_PeakLimiter`) → output. Samples are float32 WAVs loaded
once into `AVAudioPCMBuffer`s.

Sequencer: lookahead scheduler, the proven pattern from the mock. A
`DispatchSourceTimer` on a serial queue fires every 25 ms and schedules every
hit falling inside the next 120 ms window. Beat-to-wallclock anchoring uses
host time (`AVAudioTime(hostTime:)`) captured at transport start; players are
started once and hits are scheduled with `scheduleBuffer(at:)`. Pattern edits,
tempo, and swing changes are picked up at the scheduling horizon (≤120 ms),
which is how the mock behaves and feels right.

Concurrency contract: the scheduler queue owns an immutable `Pattern` (plus
tempo/swing/mute/solo) snapshot. Every UI edit sends a fresh value copy via
`queue.async`; the scheduler never reads shared mutable state, the UI never
touches the queue's state. Value semantics make snapshots free.

Choke (v1 simplification): when a closed hat is scheduled at T, the open-hat
pool is stopped by a timer aligned to T (±10 ms accuracy; musically fine,
documented). Escape hatch if it ever feels wrong: custom `AVAudioSourceNode`
sampler with sample-accurate gates (v2).

Live triggers (QWERTY/MIDI) call `trigger(voice, velocity)` immediately: same
pools, `scheduleBuffer(at: nil)`.

Offline bounce: a second engine in `.offline` manual-rendering mode renders N
loops of the current pattern deterministically (sample-time scheduling from 0)
to a float32 WAV. One implementation serves WAV export and the engine's own
smoke test (bounce 2 loops of the House seed, assert duration and RMS > floor).

## MIDI input (TaktMIDI)

`MIDIClientCreate` + `MIDIInputPortCreateWithProtocol(._1_0)`, all sources
connected, hot-plug via setup-changed notifications. Note-on → voice via the
kit's `gmNote` map; velocity passes through. Tuned for keyboard controllers
first (user's hardware): the C1–A1 octave lands on the eight voices out of the
box. Learn mode is v1.1; the project model carries a `midiOverrides` dict from
day one so learn lands without a schema change.

## Persistence & export

Play first, file second (PRODUCT.md principle 4): the app owns one implicit
session project autosaved (debounced, atomic) to
`~/Library/Application Support/takt/session.takt`. No open/save ceremony at
launch, ever. `File > Save As…`/`Open…` read and write `.takt` files (JSON,
`schemaVersion` field for migration).

Exports:
- **WAV**: offline bounce, 1 loop (48 kHz float32; format options later).
- **MIDI**: SMF type 0 written by a pure `TaktCore` function; swing baked into
  tick offsets (960 PPQN), velocities as stored, GM note numbers. Golden-byte
  tests.
- **Drag-out**: grid header exposes a `Transferable` `FileRepresentation` that
  renders to a temp file on demand; drop into Finder/DAW.

## UI (takt app)

- **Theme tokens**: `Theme` struct mirroring DESIGN.md, three colorways, Candy
  default (persisted in `UserDefaults`). Colors authored in OKLCH and converted
  to sRGB by a small exact converter (~30 lines), so the app matches the mock
  to the digit.
- **Pattern grid**: one custom `NSView` (hosted via `NSViewRepresentable`)
  drawing all lanes/cells and the playhead; mouse semantics exactly like the
  mock (click toggle, right-click velocity cycle, left-drag paint). Scroll-on-
  cell fine velocity is a nice-to-have, not a v1 gate. Redraw driven by a
  display link only while playing. SwiftUI renders everything around it
  (transport, lane headers, status bar).
- **Transport**: play/stop (space), BPM drag/steppers (50–200), swing slider
  (50–75%), seed chips (House/Breaks/Hip-Hop/Techno from TaktCore), clear,
  beat LED.
- **Lane headers**: color dot (flashes on trigger), name, M/S. QWERTY jam on
  A S D F G H J K via a local `NSEvent` key monitor.

## Testing & verification

- `TaktCoreTests`: swing/step timing golden values, Codable round-trips, seed
  integrity, SMF golden bytes (parsed back by a minimal reader).
- `TaktAudioTests`: offline bounce duration/RMS assertions; choke behavior
  (open-hat tail energy drops after closed hat).
- End-to-end: `make app`, launch, play seeds, jam, export; hostile-eyes agent
  reviews each landed milestone.

## Milestones

1. **M1 Core**: package scaffold, model, timing, seeds, tests green.
2. **M2 Sound**: kit renderer + baked TAKT-1 WAVs; engine + sequencer; offline
   bounce smoke test green (audible proof without UI).
3. **M3 Instrument**: SwiftUI shell + grid + transport + themes; playable app.
4. **M4 Hands**: QWERTY jam + CoreMIDI in + learn mode.
5. **M5 Keeper**: session autosave, Save As/Open, WAV/MIDI export, drag-out.

## Risks (named, with escape hatches)

- SwiftUI grid performance → custom NSView from day one (not a rewrite later).
- Choke precision via timers → AVAudioSourceNode sampler is the v2 hatch.
- SPM app packaging quirks (activation, resources) → `make app` bundle script;
  if it ever grows past that, generate an Xcode project with XcodeGen then.
- AVFoundation + Swift 6 concurrency friction → language mode v5 now, revisit.
