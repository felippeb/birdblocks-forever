# Changelog

## 0.2.0-forever - 2026-11-17

The modern update: guideline Tetris in a neon cabinet, with the retro profiles
kept as options.

### Game

- New **Modern** profile, now the default: SRS rotation with published wall-kick
  tables, 7-bag randomiser, hold, ghost piece, hard drop, 30-frame lock delay with
  up to 15 movement resets, and the guideline gravity table.
- Guideline scoring: 100 / 300 / 500 / 800 × (level + 1), T-spin mini/full
  tables, back-to-back ×1.5, combo bonuses, and perfect-clear bonuses.
- **Space** hard drops (instant lock, +2 per cell); **C** or **Shift** holds.
- Existing installs adopt the modern profile once on upgrade. `/blocks gb` and
  `/blocks snes` still select the faithful 1989 rulesets and are remembered.
- Game Boy and SNES behaviour is unchanged: Nintendo rotation, no kicks, no lock
  delay, 40 / 100 / 300 / 1200 scoring.

### Presentation

- New 320×240 neon cabinet: near-black screen, magenta well and frame, amber
  highlights, and the cyan/magenta BLOCK STACK-style piece palette.
- Hold box and a three-piece NEXT queue.
- Tiled wells for every profile, so the 1px grid stays crisp at fractional UI
  scales instead of splitting into panels.
- Line-clear flash, particle bursts, floating QUAD! / T-SPIN! / DOUBLE / TRIPLE
  text, a LEVEL banner, and a short screen shake on hard drops and quads.

### Audio

- Two new synthesized SFX: `hard.ogg` for hard drops and `hold.ogg` for swaps.

### Tooling

- 144 engine assertions (up from 99), 87 addon assertions (up from 70), and the
  same 20,000-frame stress run, now covering the modern rules.
- OGG stream serials are normalized after encoding, so regenerating the audio is
  byte-for-byte reproducible instead of rewriting every file.
- Screenshot set regenerated for modern, Game Boy and SNES.

## 0.1.0 - 2026-11-17

First release.

### Game

- Faithful 10×18 Game Boy profile and 10×20 NES profile, both at 60 Hz with the
  original frame tables for gravity, DAS, ARR, ARE and line-clear animation.
- Nintendo rotation (left-handed on Game Boy, right-handed on NES), no wall kicks,
  no lock delay, no hold, no hard drop.
- Nintendo scoring: 40 / 100 / 300 / 1200 × (level + 1), soft drop +1 per cell.
- No piece repeats twice in a row; start level 0–9, level up every 10 lines.
- High scores per profile in SavedVariables.

### Presentation

- 256×256 TGA atlas with NEAREST filtering: Game Boy four-shade green palette and
  colored NES blocks, plus a 5×7 bitmap font.
- Animated bird on the title screen; line-clear blink; pause and game-over overlays.
- Pooled quads, integer zoom 1–8 or auto-fit, movable window.

### Audio

- Synthesized square/triangle/noise SFX for move, rotate, lock, line, tetris,
  level-up, pause, game over and start.
- Original OGG Vorbis arrangement of the public-domain *Korobeiniki*, looped by
  re-arming from the render loop. No Nintendo samples.

### Forever integration

- Opens automatically 1.5 s after the player boards a flight-path taxi, starts
  playing immediately, and closes 2 s after landing.
- Pauses and closes in combat, reopens when combat ends while still flying.
- Reopening resumes a paused run; a top-out followed by another flight starts a
  fresh game rather than leaving a GAME OVER screen up.
- Closing the window mid-flight keeps it closed for the rest of that flight
  instead of popping back open a second later.
- Music follows play: it stops on pause and game over and restarts on resume.
- `/blocks` and `/bb` commands for profile, zoom, start level, audio and scores.
- Keyboard input is captured only while the window is open.

### Tooling

- `tools/make_assets.py` regenerates every generated asset and Lua table.
- Offline test suites for the engine and the addon, plus a rasterizer that turns
  the real draw calls into screenshots.
- Release pipeline: archive build, content audit, CurseForge upload, GitHub release.
