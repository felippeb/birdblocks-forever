#!/usr/bin/env python3
"""Build every byte of Bird Blocks that is not hand-written Lua.

The addon draws with WoW textures, so the art is a single uncompressed TGA
atlas of 8x8 tiles and 5x7 glyphs. Audio is synthesized square/triangle/noise
into 16-bit mono WAVs: no sampled Nintendo audio, no external files.

Everything here is deterministic: same input bytes, same output bytes.

    python tools/make_assets.py            # write assets + generated Lua
    python tools/make_assets.py --preview  # also write a 4x atlas preview PNG

Melody: Korobeiniki, a Russian folk song in the public domain. This is an
original square-wave arrangement of that melody, not a transcription of any
recording or of Nintendo's arrangement.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ADDON = ROOT / "BirdBlocks"
ATLAS_SIZE = 256
SLOT_PITCH = 16
ART = 8

# --------------------------------------------------------------------------- palette

GB_DARKEST = (15, 56, 15, 255)      # #0f380f
GB_DARK = (48, 98, 48, 255)         # #306230
GB_LIGHT = (139, 172, 15, 255)      # #8bac0f
GB_LIGHTEST = (155, 188, 15, 255)   # #9bbc0f

# SNES/NES piece colours
PIECE_COLORS = {
    "I": (0, 240, 240),
    "J": (0, 64, 240),
    "L": (240, 128, 0),
    "O": (240, 240, 0),
    "S": (0, 216, 0),
    "T": (192, 0, 240),
    "Z": (240, 0, 0),
}

# --------------------------------------------------------------------------- font
# 5x7 upper-case pixel font. Drawn white so the game can tint it.
FONT = {
    "A": (".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
    "B": ("####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."),
    "C": (".####", "#....", "#....", "#....", "#....", "#....", ".####"),
    "D": ("####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."),
    "E": ("#####", "#....", "#....", "####.", "#....", "#....", "#####"),
    "F": ("#####", "#....", "#....", "####.", "#....", "#....", "#...."),
    "G": (".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."),
    "H": ("#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
    "I": ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"),
    "J": ("..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."),
    "K": ("#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"),
    "L": ("#....", "#....", "#....", "#....", "#....", "#....", "#####"),
    "M": ("#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"),
    "N": ("#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"),
    "O": (".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    "P": ("####.", "#...#", "#...#", "####.", "#....", "#....", "#...."),
    "Q": (".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"),
    "R": ("####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"),
    "S": (".####", "#....", "#....", ".###.", "....#", "....#", "####."),
    "T": ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."),
    "U": ("#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    "V": ("#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."),
    "W": ("#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"),
    "X": ("#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"),
    "Y": ("#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."),
    "Z": ("#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"),
    "0": (".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."),
    "1": ("..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."),
    "2": (".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"),
    "3": ("####.", "....#", "....#", ".###.", "....#", "....#", "####."),
    "4": ("...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."),
    "5": ("#####", "#....", "####.", "....#", "....#", "#...#", ".###."),
    "6": (".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."),
    "7": ("#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."),
    "8": (".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."),
    "9": (".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."),
    " ": (".....", ".....", ".....", ".....", ".....", ".....", "....."),
    ":": (".....", "..#..", "..#..", ".....", "..#..", "..#..", "....."),
    "-": (".....", ".....", ".....", "#####", ".....", ".....", "....."),
    ".": (".....", ".....", ".....", ".....", ".....", ".##..", ".##.."),
    ",": (".....", ".....", ".....", ".....", ".##..", ".##..", ".#..."),
    "!": ("..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."),
    "?": (".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."),
    "/": ("....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."),
    "<": ("...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."),
    ">": (".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."),
    "+": (".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."),
    "=": (".....", ".....", "#####", ".....", "#####", ".....", "....."),
}

# --------------------------------------------------------------------------- tiles


def block_tile(dark, mid, light) -> Image.Image:
    """One 8x8 block with a chunky bevel, readable at 3x and 4x."""
    img = Image.new("RGBA", (ART, ART), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 7, 7], fill=dark)
    d.rectangle([1, 1, 6, 6], fill=mid)
    d.line([1, 1, 6, 1], fill=light)
    d.line([1, 1, 1, 6], fill=light)
    d.rectangle([3, 3, 4, 4], fill=dark)
    return img


def empty_tile(bg, dot, dotted: bool) -> Image.Image:
    img = Image.new("RGBA", (ART, ART), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 7, 7], fill=bg)
    if dotted:
        for x, y in ((1, 1), (5, 1), (1, 5), (5, 5)):
            d.point((x, y), fill=dot)
    return img


def glyph_tile(rows) -> Image.Image:
    img = Image.new("RGBA", (ART, ART), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "#":
                d.point((x, y), fill=(255, 255, 255, 255))
    return img


def snes_block_tile() -> Image.Image:
    """White/grey shading; vertex colour supplies the piece colour."""
    img = Image.new("RGBA", (ART, ART), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 7, 7], fill=(90, 90, 90, 255))
    d.rectangle([1, 1, 6, 6], fill=(255, 255, 255, 255))
    d.line([1, 1, 6, 1], fill=(255, 255, 255, 255))
    d.line([1, 1, 1, 6], fill=(250, 250, 250, 255))
    d.line([6, 2, 6, 6], fill=(150, 150, 150, 255))
    d.line([2, 6, 5, 6], fill=(150, 150, 150, 255))
    d.rectangle([3, 3, 4, 4], fill=(225, 225, 225, 255))
    return img


# A 24x16 bird seen side-on, head and beak to the right, tail to the left.
# Two frames differ only in wing height; the title screen flaps between them.
# Drawn with shapes rather than ASCII art so the silhouette stays smooth.
BIRD_W, BIRD_H = 24, 16


def bird_frame(wing_up: bool) -> Image.Image:
    img = Image.new("RGBA", (BIRD_W, BIRD_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = (255, 255, 255, 255)
    # tail
    d.polygon([(0, 5), (5, 6), (5, 10), (0, 11)], fill=w)
    # body and head
    d.ellipse([4, 4, 17, 12], fill=w)
    d.ellipse([13, 3, 21, 11], fill=w)
    # beak
    d.polygon([(20, 5), (23, 7), (20, 9)], fill=w)
    # wing
    if wing_up:
        d.polygon([(5, 8), (12, 0), (16, 7)], fill=w)
    else:
        d.polygon([(5, 8), (15, 15), (6, 13)], fill=w)
    # eye: punch a hole so the screen colour shows through
    d.point((17, 5), fill=(0, 0, 0, 0))
    return img


# --------------------------------------------------------------------------- atlas


def slot_rect(index: int):
    col = index % (ATLAS_SIZE // SLOT_PITCH)
    row = index // (ATLAS_SIZE // SLOT_PITCH)
    x = col * SLOT_PITCH + (SLOT_PITCH - ART) // 2
    y = row * SLOT_PITCH + (SLOT_PITCH - ART) // 2
    return x, y, x + ART, y + ART


def build_atlas():
    atlas = Image.new("RGBA", (ATLAS_SIZE, ATLAS_SIZE), (0, 0, 0, 0))
    slots = {}
    order = []

    def add(name, image, rect=None):
        if rect is None:
            rect = slot_rect(len(order))
        atlas.paste(image, (rect[0], rect[1]))
        slots[name] = rect
        order.append(name)

    add("gb_block", block_tile(GB_DARKEST, GB_DARK, GB_LIGHT))
    add("gb_empty", empty_tile(GB_LIGHTEST, GB_LIGHT, True))
    add("snes_block", snes_block_tile())
    add("snes_empty", empty_tile((6, 6, 10, 255), (26, 26, 36, 255), True))
    add("dot", empty_tile((0, 0, 0, 0), (70, 70, 90, 255), True))
    for ch in FONT:
        add("font_" + ch, glyph_tile(FONT[ch]))

    # Birds live at the bottom-left, outside the 8x8 slot grid.
    bird_a_rect = (0, 224, BIRD_W, 224 + BIRD_H)
    bird_b_rect = (BIRD_W, 224, BIRD_W * 2, 224 + BIRD_H)
    add("bird_a", bird_frame(True), bird_a_rect)
    add("bird_b", bird_frame(False), bird_b_rect)

    return atlas, slots


def slot_uv(rect):
    x0, y0, x1, y1 = rect
    return (x0 / ATLAS_SIZE, y0 / ATLAS_SIZE, x1 / ATLAS_SIZE, y1 / ATLAS_SIZE)


def write_atlas_lua(slots):
    lines = [
        "-- Generated by tools/make_assets.py. Do not edit.",
        "BirdBlocksAtlas = {",
        '\tpath = "Interface\\\\AddOns\\\\BirdBlocks\\\\tiles.tga",',
        f"\tsize = {ATLAS_SIZE},",
        "\tslots = {",
    ]
    for name, rect in slots.items():
        u0, v0, u1, v1 = slot_uv(rect)
        key = name if not name.startswith("font_") else "glyph:" + name[5:]
        if key.startswith("glyph:"):
            lines.append(
                '\t\t[%r] = { %.8f, %.8f, %.8f, %.8f },'
                % (key, u0, v0, u1, v1)
            )
        else:
            lines.append(
                '\t\t%s = { %.8f, %.8f, %.8f, %.8f },'
                % (key, u0, v0, u1, v1)
            )
    lines += ["\t},", "}", ""]
    (ADDON / "src" / "generated_atlas.lua").write_text("\n".join(lines), encoding="utf-8")


# --------------------------------------------------------------------------- audio

SAMPLE_RATE = 22050

# name -> seconds, filled in as audio is written; drives the generated Lua.
AUDIO = {}


def midi_hz(note: str) -> float:
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
             "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    if note == "R":
        return 0.0
    if len(note) == 2:
        name, octave = note[0], int(note[1])
    else:
        name, octave = note[:2], int(note[2])
    midi = 12 * (octave + 1) + names[name]
    return 440.0 * (2 ** ((midi - 69) / 12))


def adsr(i: int, n: int, attack=0.005, release=0.04, sustain=1.0):
    t = i / SAMPLE_RATE
    dur = n / SAMPLE_RATE
    if t < attack:
        return t / attack
    if t > dur - release:
        return max(0.0, (dur - t) / release) * sustain
    return sustain


def pulse(phase: float, duty: float) -> float:
    return 1.0 if (phase % 1.0) < duty else -1.0


def triangle(phase: float) -> float:
    p = phase % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def lowpass(samples, alpha=0.35):
    out = []
    prev = 0.0
    for s in samples:
        prev += alpha * (s - prev)
        out.append(prev)
    return out


def to_ogg(path: Path, samples):
    """Write 16-bit mono OGG Vorbis. PlaySoundFile only reliably takes ogg."""
    import soundfile as sf

    peak = max(1e-9, max(abs(s) for s in samples))
    if peak > 0.999:
        samples = [s * 0.999 / peak for s in samples]
    sf.write(str(path), samples, SAMPLE_RATE, format="OGG", subtype="VORBIS")
    AUDIO[path.stem] = round(len(samples) / SAMPLE_RATE, 3)


def note_track(events, total_seconds, wave_fn, duty=0.5, volume=0.5, vib=0.0):
    """events: list of (start_s, duration_s, hz). Renders a monophonic track."""
    n = int(total_seconds * SAMPLE_RATE)
    buf = [0.0] * n
    for start, dur, hz in events:
        if hz <= 0:
            continue
        i0 = int(start * SAMPLE_RATE)
        ns = int(dur * SAMPLE_RATE)
        phase = 0.0
        for i in range(ns):
            idx = i0 + i
            if idx >= n:
                break
            f = hz
            if vib:
                f *= 1.0 + vib * math.sin(2 * math.pi * 5.5 * i / SAMPLE_RATE)
            phase += f / SAMPLE_RATE
            buf[idx] += wave_fn(phase) * volume * adsr(i, ns, 0.004, min(0.05, dur * 0.4))
    return buf


def noise_track(hits, total_seconds, volume=0.12):
    n = int(total_seconds * SAMPLE_RATE)
    buf = [0.0] * n
    rng = 123456789
    for start, dur in hits:
        i0 = int(start * SAMPLE_RATE)
        ns = int(dur * SAMPLE_RATE)
        for i in range(ns):
            idx = i0 + i
            if idx >= n:
                break
            rng = (1103515245 * rng + 12345) & 0x7FFFFFFF
            noise = (rng / 0x3FFFFFFF) - 1.0
            buf[idx] += noise * volume * math.exp(-6.0 * i / ns)
    return buf


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def make_sfx(out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)

    def blip(name, seq, duty=0.25, volume=0.35):
        # seq: (duration, hz) pairs played back to back
        samples = []
        for dur, hz in seq:
            n = int(dur * SAMPLE_RATE)
            phase = 0.0
            for i in range(n):
                phase += hz / SAMPLE_RATE
                samples.append(pulse(phase, duty) * volume * adsr(i, n, 0.002, min(0.03, dur * 0.6)))
        to_ogg(out_dir / (name + ".ogg"), samples)

    blip("move", [(0.028, 1046.5)], duty=0.125, volume=0.22)
    blip("rotate", [(0.030, 880.0), (0.030, 1318.5)], duty=0.25, volume=0.28)
    blip("lock", [(0.045, 196.0), (0.035, 146.8)], duty=0.5, volume=0.42)
    blip("pause", [(0.025, 659.3), (0.025, 0.0)], duty=0.5, volume=0.25)
    blip("line", [(0.055, 523.3), (0.055, 659.3), (0.055, 784.0), (0.11, 1046.5)],
         duty=0.25, volume=0.34)
    blip("tetris", [(0.06, 523.3), (0.06, 659.3), (0.06, 784.0), (0.06, 1046.5),
                    (0.06, 784.0), (0.06, 1046.5), (0.20, 1318.5)], duty=0.25, volume=0.38)
    blip("level", [(0.05, 440.0), (0.05, 554.4), (0.05, 659.3), (0.05, 880.0),
                   (0.16, 1108.7)], duty=0.25, volume=0.34)
    blip("over", [(0.10, 392.0), (0.10, 349.2), (0.10, 311.1), (0.10, 261.6),
                  (0.32, 196.0)], duty=0.5, volume=0.34)
    blip("start", [(0.05, 523.3), (0.05, 784.0), (0.12, 1046.5)], duty=0.25, volume=0.32)


def make_music(out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    bpm = 150.0
    beat = 60.0 / bpm
    q, e, h, dq = beat, beat / 2, beat * 2, beat * 1.5

    # (note, beats). Korobeiniki, public-domain melody.
    phrase = [
        ("E5", 1), ("B4", .5), ("C5", .5), ("D5", 1), ("C5", .5), ("B4", .5),
        ("A4", 1), ("A4", .5), ("C5", .5), ("E5", 1), ("D5", .5), ("C5", .5),
        ("B4", 1.5), ("C5", .5), ("D5", 1), ("E5", 1),
        ("C5", 1), ("A4", 1), ("A4", 1), ("R", 1),
    ]
    melody_notes = phrase * 4  # 16 bars, ~25.6 s
    lead = []
    t = 0.0
    for name, beats in melody_notes:
        lead.append((t, beats * beat * 0.92, midi_hz(name)))
        t += beats * beat
    total = t

    # Bass: two pulses per beat, root-fifth walking per four bars.
    bass = []
    roots = ["A2", "A2", "E2", "E2", "A2", "A2", "E2", "E2",
             "D3", "D3", "A2", "A2", "E2", "E2", "E2", "E2"]
    for bar in range(16):
        root = midi_hz(roots[bar % len(roots)])
        fifth = root * 1.4983
        for b in range(4):
            start = (bar * 4 + b) * beat
            bass.append((start, beat * 0.42, root if b % 2 == 0 else fifth))
    # Percussion on 2 and 4.
    hats = []
    for bar in range(16):
        for b in (1, 3):
            hats.append(((bar * 4 + b) * beat, 0.05))

    lead_buf = note_track(lead, total, lambda p: pulse(p, 0.25), volume=0.17, vib=0.004)
    bass_buf = note_track(bass, total, triangle, volume=0.20)
    hat_buf = noise_track(hats, total, volume=0.05)
    mixed = mix(lead_buf, bass_buf, hat_buf)
    mixed = lowpass(mixed, 0.5)
    to_ogg(out_dir / "theme.ogg", mixed)


# --------------------------------------------------------------------------- main


def write_audio_lua():
    sfx = sorted(k for k in AUDIO if k != "theme")
    lines = [
        "-- Generated by tools/make_assets.py. Do not edit.",
        "BirdBlocksAudio = {",
        '\tbase = "Interface\\\\AddOns\\\\BirdBlocks\\\\",',
        '\ttheme = "music\\\\theme.ogg",',
        f"\tthemeLength = {AUDIO.get('theme', 0.0):.3f},",
        "\tsfx = {",
    ]
    for name in sfx:
        lines.append(f'\t\t{name} = "sfx\\\\{name}.ogg",')
    lines += ["\t},", "}", ""]
    (ADDON / "src" / "generated_audio.lua").write_text("\n".join(lines), encoding="utf-8")


def write_icon(atlas, slots, path: Path):
    """64x64 TGA for the addon list: four blocks and a bird on GB green."""
    icon = Image.new("RGBA", (64, 64), GB_LIGHTEST)
    block = atlas.crop(slots["gb_block"]).resize((16, 16), Image.NEAREST)
    for i in range(4):
        icon.alpha_composite(block, (i * 16, 48))
    bird = atlas.crop(slots["bird_a"]).resize((48, 32), Image.NEAREST)
    solid = Image.new("RGBA", bird.size, GB_DARKEST)
    icon.paste(solid, (8, 8), bird)
    icon.save(path, format="TGA", compression=None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()

    (ADDON / "src").mkdir(parents=True, exist_ok=True)
    (ADDON / "sfx").mkdir(parents=True, exist_ok=True)
    (ADDON / "music").mkdir(parents=True, exist_ok=True)
    (ROOT / "docs").mkdir(parents=True, exist_ok=True)

    atlas, slots = build_atlas()
    atlas_path = ADDON / "tiles.tga"
    # TGA, uncompressed, 32-bit BGRA with alpha (WoW reads this happily).
    atlas.save(atlas_path, format="TGA", compression=None)

    write_atlas_lua(slots)
    make_sfx(ADDON / "sfx")
    make_music(ADDON / "music")
    write_audio_lua()
    write_icon(atlas, slots, ADDON / "icon.tga")

    if args.preview:
        big = atlas.resize((ATLAS_SIZE * 4, ATLAS_SIZE * 4), Image.NEAREST)
        bg = Image.new("RGBA", big.size, (24, 24, 32, 255))
        bg.alpha_composite(big)
        bg.convert("RGB").save(ROOT / "docs" / "atlas-preview.png")
        # A mock game frame using the real tiles, useful for eyeballing the art.
        mock = Image.new("RGBA", (200, 184), GB_LIGHTEST)
        empty_tile_img = atlas.crop(slots["gb_empty"])
        block_tile_img = atlas.crop(slots["gb_block"])
        for y in range(18):
            for x in range(10):
                px, py = 16 + x * 8, 20 + y * 8
                mock.alpha_composite(empty_tile_img, (px, py))
        board = [
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "..........",
            "....##....",
            "...####...",
            "..######..",
            ".########.",
        ]
        for y, row in enumerate(board):
            for x, ch in enumerate(row):
                if ch == "#":
                    mock.alpha_composite(block_tile_img, (16 + x * 8, 20 + y * 8))
        mock.convert("RGB").resize((800, 736), Image.NEAREST).save(ROOT / "docs" / "mock-frame.png")

    print("atlas:", atlas_path, atlas_path.stat().st_size, "bytes")
    print("sfx:", len(list((ADDON / 'sfx').glob('*.ogg'))), "files")
    print("music:", (ADDON / 'music' / 'theme.ogg').stat().st_size, "bytes")
    print("audio lua:", (ADDON / 'src' / 'generated_audio.lua').stat().st_size, "bytes")


if __name__ == "__main__":
    main()
