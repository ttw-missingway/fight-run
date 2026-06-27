#!/usr/bin/env python3
"""Build a Godot SpriteFrames .tres from char3_manifest.json."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "assets" / "sprites" / "char3" / "char3_manifest.json"
OUT = ROOT / "assets" / "sprites" / "char3" / "char3_sprite_frames.tres"


def main() -> None:
    data = json.loads(MANIFEST.read_text())
    animations: dict = data["animations"]

    frame_paths: list[str] = []
    path_to_id: dict[str, str] = {}

    for anim_data in animations.values():
        for frame_path in anim_data["frames"]:
            if frame_path not in path_to_id:
                path_to_id[frame_path] = str(len(frame_paths) + 1)
                frame_paths.append(frame_path)

    lines: list[str] = []
    lines.append(
        f'[gd_resource type="SpriteFrames" load_steps={len(frame_paths) + 1} format=3]'
    )
    lines.append("")

    for i, frame_path in enumerate(frame_paths, start=1):
        lines.append(f'[ext_resource type="Texture2D" path="{frame_path}" id="{i}"]')

    lines.append("")
    lines.append("[resource]")
    lines.append("animations = [")

    anim_entries: list[str] = []
    for anim_name, anim_data in animations.items():
        fps = anim_data.get("fps", 12)
        loop = "true" if anim_data.get("loop", False) else "false"
        frame_refs = []
        for frame_path in anim_data["frames"]:
            rid = path_to_id[frame_path]
            frame_refs.append('{\n"duration": 1.0,\n"texture": ExtResource("%s")\n}' % rid)
        frames_block = ",\n".join(frame_refs)
        anim_entries.append(
            "{\n"
            f'"frames": [{frames_block}],\n'
            f'"loop": {loop},\n'
            f'"name": &"{anim_name}",\n'
            f'"speed": {float(fps)}\n'
            "}"
        )

    lines.append(",\n".join(anim_entries))
    lines.append("]")
    lines.append("")

    OUT.write_text("\n".join(lines))
    print(f"Wrote {OUT} ({len(frame_paths)} textures, {len(animations)} animations)")


if __name__ == "__main__":
    main()
