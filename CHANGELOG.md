# Changelog

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
- Music follows play: it stops on pause and game over and restarts on resume.
- `/blocks` and `/bb` commands for profile, zoom, start level, audio and scores.
- Keyboard input is captured only while the window is open.

### Tooling

- `tools/make_assets.py` regenerates every generated asset and Lua table.
- Offline test suites for the engine and the addon, plus a rasterizer that turns
  the real draw calls into screenshots.
- Release pipeline: archive build, content audit, CurseForge upload, GitHub release.
