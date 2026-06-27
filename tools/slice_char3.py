#!/usr/bin/env python3
"""Slice Asset Bakery Char_3 sprite sheet into per-frame PNGs + animation manifest."""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

from PIL import Image

# Source sheet (override with argv[1]).
DEFAULT_SRC = (
    Path(__file__).resolve().parents[1]
    / ".cursor"
    / "projects"
    / "Users-dylanwalling-fight-run"
    / "assets"
    / "Char_3-46e73822-0abd-4dce-9bb5-745e6c8687b4.png"
)
OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "sprites" / "char3"
FRAME_CANVAS = (96, 96)
FOOT_X = FRAME_CANVAS[0] // 2
FOOT_Y = FRAME_CANVAS[1]

# Per content row: animation name -> [start_blob, count] (blob indices in that row).
ROW_ANIMATIONS = [
    {"idle": [0, 10], "crouch": [10, 6], "dash": [16, 6]},
    {"run": [0, 3]},
    {"jump": [0, 21]},
    {"attack": [0, 12]},
    {"block": [0, 6], "projectile": [6, 6]},
    {"hit": [0, 8], "knockdown_air": [8, 4], "knockdown_ground": [12, 4]},
    {},  # FX row — skipped
]


def is_content(px: tuple[int, int, int, int]) -> bool:
    r, g, b, a = px
    if a < 10:
        return False
    if r + g + b < 25:
        return False
    if b > 180 and r < 80 and g < 120 and b > r + 60:
        return False
    return True


def find_row_bands(img: Image.Image) -> list[tuple[int, int]]:
    w, h = img.size
    row_has = [0] * h
    for y in range(h):
        for x in range(w):
            if is_content(img.getpixel((x, y))):
                row_has[y] += 1

    raw: list[tuple[int, int]] = []
    in_band = False
    start = 0
    for y in range(h):
        if row_has[y] > 0 and not in_band:
            in_band = True
            start = y
        elif row_has[y] == 0 and in_band:
            in_band = False
            raw.append((start, y))
    if in_band:
        raw.append((start, h))

    # Drop 1–2px noise slivers between main rows.
    bands = [b for b in raw if b[1] - b[0] >= 8]
    return bands


def find_row_blobs(img: Image.Image, y0: int, y1: int) -> list[tuple[int, int, int, int]]:
    w, _h = img.size
    col_has = [0] * w
    for y in range(y0, y1):
        for x in range(w):
            if is_content(img.getpixel((x, y))):
                col_has[x] += 1

    x_ranges: list[tuple[int, int]] = []
    in_blob = False
    xs = 0
    for x in range(w):
        if col_has[x] > 0 and not in_blob:
            in_blob = True
            xs = x
        elif col_has[x] == 0 and in_blob:
            in_blob = False
            x_ranges.append((xs, x))
    if in_blob:
        x_ranges.append((xs, w))

    blobs: list[tuple[int, int, int, int]] = []
    for x0, x1 in x_ranges:
        bx0, by0, bx1, by1 = x1, y1, x0, y0
        for y in range(y0, y1):
            for x in range(x0, x1):
                if is_content(img.getpixel((x, y))):
                    bx0 = min(bx0, x)
                    by0 = min(by0, y)
                    bx1 = max(bx1, x + 1)
                    by1 = max(by1, y + 1)
        if bx1 > bx0 and by1 > by0:
            blobs.append((bx0, by0, bx1, by1))
    return blobs


def make_transparent(crop: Image.Image) -> Image.Image:
    px = crop.load()
    w, h = crop.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if r + g + b < 30:
                px[x, y] = (0, 0, 0, 0)
    return crop


def normalize_frame(crop: Image.Image) -> Image.Image:
    crop = make_transparent(crop)
    canvas = Image.new("RGBA", FRAME_CANVAS, (0, 0, 0, 0))
    cw, ch = crop.size
    paste_x = FOOT_X - cw // 2
    paste_y = FOOT_Y - ch
    canvas.paste(crop, (paste_x, paste_y), crop)
    return canvas


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.exists():
        # Fallback: user-attached asset path in cursor projects folder.
        alt = Path(
            "/Users/dylanwalling/.cursor/projects/Users-dylanwalling-fight-run/assets/"
            "Char_3-46e73822-0abd-4dce-9bb5-745e6c8687b4.png"
        )
        src = alt if alt.exists() else src

    if not src.exists():
        print(f"Missing source sheet: {src}", file=sys.stderr)
        sys.exit(1)

    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    frames_dir = OUT_DIR / "frames"
    frames_dir.mkdir(parents=True)

    sheet_copy = OUT_DIR / "char3_sheet.png"
    shutil.copy2(src, sheet_copy)

    img = Image.open(src).convert("RGBA")
    bands = find_row_bands(img)
    print(f"Sheet {img.size[0]}x{img.size[1]}, {len(bands)} content rows")

    animations: dict[str, dict] = {}
    frame_index = 0

    for row_i, (y0, y1) in enumerate(bands):
        blobs = find_row_blobs(img, y0, y1)
        print(f"  row {row_i}: y={y0}-{y1}, blobs={len(blobs)}")
        if row_i >= len(ROW_ANIMATIONS):
            continue
        row_map = ROW_ANIMATIONS[row_i]
        if not row_map:
            continue

        for anim_name, (start, count) in row_map.items():
            files: list[str] = []
            for bi in range(start, min(start + count, len(blobs))):
                box = blobs[bi]
                crop = img.crop(box)
                norm = normalize_frame(crop)
                fname = f"frame_{frame_index:04d}.png"
                norm.save(frames_dir / fname)
                files.append(f"res://assets/sprites/char3/frames/{fname}")
                frame_index += 1
            if files:
                animations[anim_name] = {
                    "frames": files,
                    "fps": 10 if anim_name in ("idle", "block") else 12,
                    "loop": anim_name
                    in ("idle", "run", "crouch", "block", "jump"),
                }

    manifest = {
        "sheet": "res://assets/sprites/char3/char3_sheet.png",
        "frame_size": list(FRAME_CANVAS),
        "foot": [FOOT_X, FOOT_Y],
        "animations": animations,
    }
    manifest_path = OUT_DIR / "char3_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))
    print(f"Wrote {frame_index} frames -> {frames_dir}")
    print(f"Manifest -> {manifest_path}")

    import subprocess

    build_script = Path(__file__).resolve().parent / "build_char3_sprite_frames.py"
    subprocess.run([sys.executable, str(build_script)], check=True)


if __name__ == "__main__":
    main()
