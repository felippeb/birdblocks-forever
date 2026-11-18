# Bird Blocks

[![ci](https://github.com/felippeb/birdblocks-forever/actions/workflows/ci.yml/badge.svg)](https://github.com/felippeb/birdblocks-forever/actions/workflows/ci.yml)

Tetris, playable **on the flight-path bird** in **WoW Forever**
(interface `16001`, game version `1.60.1`).

Get on a taxi, and the game opens by itself ready to play. Land, and it closes.
No buttons, no menus, no addon config to learn.

![Modern mode](docs/screenshot-modern-game.png)

## What it is

A real, from-scratch Tetris clone for Forever — not a skin over something else.
Three rulesets share the same engine:

- **Modern** (default) — a neon arcade cabinet with guideline rules: SRS wall
  kicks, 7-bag randomiser, hold, ghost piece, lock delay, hard drop and the
  modern scoring table.
- **Game Boy** — 10×18, four shades of green, left-handed Nintendo rotation,
  no kicks, no lock delay.
- **SNES / NES** — 10×20, colored pieces, right-handed Nintendo rotation with
  the NES frame timings.

| | **Modern** | **Game Boy** | **SNES / NES** |
| --- | --- | --- | --- |
| Screen | 320×240 neon cabinet | 160×144, four greens | 256×224, colored |
| Field | 10×20 | 10×18 | 10×20 |
| Gravity | 60 frames/row at level 0 | 53 frames/row | 48 frames/row |
| DAS / ARR | 10 / 1 frames | 24 / 6 frames | 16 / 6 frames |
| ARE | 4 frames | 2 frames | 12 frames |
| Rotation | SRS + wall kicks | left-handed Nintendo | right-handed Nintendo |
| Extras | hold, ghost, hard drop, lock delay | — | — |
| Scoring | 100 / 300 / 500 / 800 × (level + 1), T-spins, B2B, combos, perfect clears | 40 / 100 / 300 / 1200 × (level + 1) | same |
| Randomiser | 7-bag | no immediate repeat | no immediate repeat |
| Levels | 0–20 | 0–20 | 0–29 |

Everything advances in **60 Hz frames**. The retro profiles use the real frame
tables from the originals rather than approximations in seconds; the modern
profile uses the guideline timings.

![Game Boy mode](docs/screenshot-gb-game.png)

## Controls

| Key | Action |
| --- | --- |
| ← → | Move (DAS then auto-shift) |
| ↓ | Soft drop (+1 per cell) |
| ↑ / X / W | Rotate clockwise |
| Z / Ctrl | Rotate counter-clockwise |
| Space | Hard drop (+2 per cell, modern only) |
| C / Shift | Hold (modern only) |
| Enter | Start, or restart after game over |
| P / Esc | Pause (Esc closes when already paused) |
| M | Music on/off |
| Mouse wheel | Zoom |

The window is movable (drag the title bar). Arrow keys and the mouse wheel are
consumed while it is open, so nothing leaks to the world.

## Taxi behaviour

- Opens **1.5 s** after `UnitOnTaxi("player")` becomes true, and starts a game
  immediately — Enter also works, it is not a title-screen stop.
- Closes **2 s** after the flight ends.
- Closes instantly in combat and reopens when combat ends if you are still flying.
- One automatic open per flight: close it mid-air and it stays closed until the
  next taxi.
- Leaving the game paused (or closing it) stops the music; nothing plays on the ground.
- `/blocks auto` turns the automatic behaviour off entirely.

## Install

### WoWUp

Addons → **Install from URL** → `https://github.com/felippeb/birdblocks-forever`

WoWUp's Forever provider only accepts a release asset whose name ends in
`-forever.zip`, so the release zip is `BirdBlocks-<version>-forever.zip`.

### Manual

1. Download the latest zip from [Releases](../../releases).
2. Extract it so that `Interface\AddOns\BirdBlocks\` exists.
3. Restart the client — new folders are only read at startup.
4. After editing any `.lua`, `/reload` is enough.

Releases are published on GitHub. The CurseForge job is wired into the same tag
pipeline and starts uploading as soon as the project id is configured.

## Commands

```text
/blocks                 open or close
/blocks modern | gb | snes   pick the version
/blocks auto            auto-open on taxi on/off
/blocks music | sound   toggle audio
/blocks zoom N          1..8, 0 = fit the screen
/blocks level N         starting level 0..9
/blocks reset           clear high scores
/blocks help            summary
```

`/bb` is a shorter alias. High scores are kept per profile in `BirdBlocksDB`.
Existing installs adopt the modern profile once on upgrade; an explicit
`/blocks gb` or `/blocks snes` always wins.

## Audio

All sound is synthesized by `tools/make_assets.py`: square/triangle/noise style
blips and an original arrangement of the public-domain folk tune *Korobeiniki*,
shipped as mono OGG Vorbis. No Nintendo samples or recordings are included.

## How it is built

| Path | What it does |
| --- | --- |
| `src/engine.lua` | Pure Lua game logic: frame tables, DAS, ARE, SRS, 7-bag, hold, hard drop, lock delay, clears, scoring, top-out |
| `src/view.lua` | Layouts, palettes and effects for all three profiles |
| `src/render.lua` | Pooled quads from one 256×256 TGA atlas, NEAREST filtering |
| `src/sound.lua` | `PlaySoundFile` SFX, looped theme |
| `src/ui.lua` | Window, keyboard, taxi/combat, slash commands, SavedVariables |
| `tools/make_assets.py` | Regenerates the atlas, icon, SFX, music and generated Lua |

`src/generated_atlas.lua` and `src/generated_audio.lua` are generated; edit the
generator, not the output.

### Tests

```powershell
lua tests\run_engine.lua      # timings, DAS, SRS kicks, 7-bag, hold, scoring, top-out
lua tests\run_ui.lua          # addon against a mock client: taxi, combat, keys, slash
lua tests\run_stress.lua      # 20,000 randomised frames, invariant-checked
lua tests\screenshots.lua     # writes draw lists to tests\out
python tests\rasterize.py tests\out   # turns them into PNGs
```

The mock client (`tests/wow_mock.lua`) records every texture the renderer touches,
so the screenshots above are the same quad calls the game makes in game.

## Publishing

The tag-driven pipeline (CI, CurseForge upload, GitHub release) is documented in
[docs/publishing.md](docs/publishing.md).

## Compatibility

Verified on WoW Forever `1.60.1` / interface `16001`. Uses only APIs already
present in that client (`UnitOnTaxi`, `PlaySoundFile`, `CreateFrame`,
`SetPropagateKeyboardInput`). Not affiliated with or endorsed by Blizzard
Entertainment, Nintendo, or CurseForge.

## License

MIT — see [LICENSE](LICENSE). *Tetris* is a trademark of Tetris Holding; this is
an independent, non-commercial homage with original code, art and audio. See
[NOTICE](NOTICE).
