# takt design system

Three colorways, one instrument. **Candy is the default appearance**; Tungsten
and Linen ship as user-selectable options. Layout, rules, and component
vocabulary never change between colorways, only the token values.

Scene sentences:
- **Candy** (default): daylight and play, sugar-glass brights on vanilla cream,
  the grid reads like a box of gumdrops.
- **Tungsten**: evening, dim room, one desk lamp, stage-dark warmth (not
  blue-black neon).
- **Linen**: long daytime sessions, lowest stimulus, warm gray-green paper
  (deliberately not sepia cream).

## Color (OKLCH)

Chrome is Restrained; the grid carries a disciplined full palette where hue
identifies the voice and brightness encodes velocity. Constants across all
colorways: hue names the voice, brightness is velocity, chrome stays quiet, one
ember-family accent for transport/record only.

| token        | candy (default)              | tungsten                  | linen |
|--------------|------------------------------|---------------------------|-------|
| bg           | oklch(0.92 0.03 345)         | oklch(0.13 0.006 70)      | oklch(0.885 0.008 100) |
| surface      | oklch(0.972 0.012 85)        | oklch(0.185 0.008 65)     | oklch(0.945 0.006 95) |
| raised       | oklch(0.945 0.018 350)       | oklch(0.22 0.009 65)      | oklch(0.92 0.007 95) |
| cell         | oklch(0.915 0.014 340)       | oklch(0.245 0.008 65)     | oklch(0.88 0.007 95) |
| cell-beat    | oklch(0.885 0.018 340)       | oklch(0.275 0.009 65)     | oklch(0.855 0.009 95) |
| line         | oklch(0.86 0.025 345)        | oklch(0.30 0.01 65)       | oklch(0.82 0.009 95) |
| text         | oklch(0.34 0.06 30)          | oklch(0.93 0.012 85)      | oklch(0.33 0.015 80) |
| dim          | oklch(0.50 0.05 25)          | oklch(0.63 0.015 75)      | oklch(0.47 0.015 80) |
| faint        | oklch(0.64 0.035 25)         | oklch(0.45 0.012 70)      | oklch(0.60 0.012 85) |
| accent       | oklch(0.66 0.20 35)          | oklch(0.70 0.185 45)      | oklch(0.56 0.115 42) |
| on-accent    | oklch(0.99 0.01 90)          | oklch(0.16 0.02 45)       | oklch(0.97 0.01 90) |

Voice hues (lane identity) are fixed angles:
kick 40 · snare 20 · clap 345 · rim 300 · closed hat 95 · open hat 150 · tom 250 · cowbell/perc 200.

Per-colorway voice rendering `oklch(VL VC hue)` and velocity alphas:
- candy: VL 0.72, VC 0.17 (accent step 0.68/0.20), alphas 0.40/0.78/1.0, glow 0.45,
  cell radius 10px, gumdrop gloss `inset 0 1px 0 oklch(1 0 0 / 0.55)` on filled steps.
- tungsten: VL 0.76, VC 0.135 (accent step 0.78/0.145), alphas 0.38/0.75/1.0, glow 0.35, radius 6px.
- linen: VL 0.66, VC 0.085 (accent step 0.56/0.10), alphas 0.45/0.80/1.0, glow 0.18, radius 6px.

Velocity = alpha/luminance of the lane hue: soft / normal / accent (+ glow).
Never use a voice hue in chrome; never use the accent inside the grid.

## Typography

Two native faces, no webfonts:
- UI labels, numerics, silkscreen text: `ui-monospace` (SF Mono), 10–13px,
  uppercase labels letterspaced 0.08em, `font-variant-numeric: tabular-nums`.
- Prose (dialogs, notes, empty states): `-apple-system` (SF Pro), 13–15px.
Scale ratio ~1.2. BPM readout is the largest number on screen.

## Layout

- One window, no navigation. Transport on top, grid center, context strip below.
- Steps grouped in 4s with a wider gutter between beats; no vertical rules.
- Row height ≥ 40px, step cells rounded 6px; consistent radius vocabulary (6px
  controls, 999px chips).
- Density is welcome in the grid, forbidden in the chrome.

## Motion

- 120–200ms, ease-out only. Motion conveys state: step trigger flash, playhead
  sweep, mute dim. Nothing decorative, nothing on load.
- Playhead and trigger flashes are transform/opacity/box-shadow only, never layout.
- Respect `prefers-reduced-motion`: keep playhead position, drop flashes.

## Components

- Buttons: 6px radius, raised surface, 1px line border; accent fill only for
  play/record and primary confirm.
- Chips (pattern slots, kit picker): pill, mono label, accent ring when active.
- Sliders: native-feel horizontal range, accent thumb, value readout to the right.
- Every control ships default / hover / focus-visible / active / disabled.
