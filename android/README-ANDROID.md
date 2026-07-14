# TAKT Run — Android companion (chapter two, R1)

A player plus tempo instrument for running: pick a beat made in TAKT on the
Mac, start it, push the tempo around mid-stride. See ../CHAPTER2.md for the
full proposal.

## Install on your phone (sideload)

1. On the phone: Settings → About phone → tap "Build number" 7 times
   (enables Developer options), then Settings → Developer options → enable
   **USB debugging**.
2. Plug the phone into the Mac with USB-C, tap "Allow" on the phone when the
   debugging prompt appears.
3. From the repo root:

   ```sh
   .toolchain/android-sdk/platform-tools/adb install android/app/build/outputs/apk/debug/app-debug.apk
   ```

   No cable? Copy `app-debug.apk` to the phone any other way (Drive, email),
   tap it, and allow "install unknown apps" when prompted.

## Getting your beats onto the phone

1. In TAKT on the Mac: **⌘S** saves the current project as a `.takt` file
   (plain JSON: every pattern block, tempo, swing).
2. Move the file to the phone: Google Drive folder, USB copy, or share it to
   yourself any way you like.
3. In TAKT Run: tap **load**, pick the file. The beat chip shows its name;
   tapping the chip cycles between your import and the built-in seeds
   (House, Breaks, Hip-Hop, Techno — the same ones as the desktop).

## On the run

- Giant **− / +**: tap for ±1 BPM, hold to sweep. Or drag the big number.
- **EASY 160 / TEMPO 170 / SPRINT 180** preset chips jump straight to a lap
  tempo. Tempo changes land within one 16th note.
- Playback runs as a foreground service: it keeps going with the screen off
  and the phone in your pocket. Stop it from the app (notification tap
  returns you there).

## Building from source

Two ways:

- **CLI** (what the repo's toolchain does): JDK 17 + Android SDK
  (platform 34, build-tools 34) + Gradle 8.10. From the repo root, with
  `JAVA_HOME`, `ANDROID_HOME` set (see `.toolchain/` if present):

  ```sh
  gradle -p android assembleDebug
  ```

- **Android Studio**: install it, open the `android/` folder, let it sync,
  press Run with your phone plugged in. Slowest download, fewest surprises.

## Architecture notes

- `Model.kt` / `Timing.kt` are line-for-line ports of TaktCore's model and
  timing math; `.takt` JSON from the desktop is the contract.
- `Engine.kt` is a software mixer feeding `AudioTrack`: the step scheduler
  lives in the sample domain (a step fires when the write cursor crosses its
  frame), so playback is gapless, tempo changes take effect at the next step,
  and hat chokes are sample-accurate.
- The TAKT-1 kit WAVs in `assets/` are the exact files the desktop plays.
- R2 (cadence follow, TTS callouts) and R3 (Wear OS remote) are described in
  ../CHAPTER2.md.
