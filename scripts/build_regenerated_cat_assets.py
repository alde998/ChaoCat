#!/usr/bin/env python3
"""Build reviewed runtime segments from the 2026-10-14 blue-screen videos.

Input is a directory of per-video PNG frame folders (bug_00000.png, ...).
Full-length, original-size GIFs are retained separately in imported-videos.
"""
import argparse
import json
import shutil
from pathlib import Path

from PIL import Image
from key_blue_video_frames import key_blue, write_gif

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "apps/macos/Assets"

# End indices are exclusive. Each clip keeps the original frame rate.
# Isolate direction-stable walking/running sections so the cat does not turn
# around while its desktop window continues moving in the opposite direction.
CLIPS = [
    ("video_1791908759713", 96, 120, 24, "walk-right", False, False),
    ("video_1791908765023", 52, 72, 24, "walk-left", False, False),
    ("video_1791908768940", 24, 56, 24, "run-right", False, False),
    ("video_1791908768940", 24, 56, 24, "run-left", True, False),
    ("video_1791908789463", 0, 24, 24, "chase-start-right", False, False),
    ("video_1791908789463", 0, 24, 24, "chase-start-left", True, False),
    ("video_1791908789463", 0, 24, 24, "chase-start-right-reverse", False, True),
    ("video_1791908789463", 0, 24, 24, "chase-start-left-reverse", True, True),
    ("video_1791908768940", 24, 56, 24, "chase-right", False, False),
    ("video_1791908768940", 24, 56, 24, "chase-left", True, False),
    ("video_1791908784602", 0, 18, 24, "chase-right-alt", False, False),
    ("video_1791908784602", 0, 18, 24, "chase-left-alt", True, False),
    ("video_1791908768940", 65, 96, 24, "pounce-right", False, False),
    ("video_1791908768940", 65, 96, 24, "pounce-left", True, False),
    ("video_1791908768940", 24, 56, 24, "frenzy-run-right", False, False),
    ("video_1791908768940", 24, 56, 24, "frenzy-run-left", True, False),
    ("video_1791909095643", 36, 124, 24, "poop", False, False),
    ("video_1791909095643", 124, 145, 24, "poop-transition", False, False),
    ("video_1791909113811", 62, 84, 30, "scratch-move-right", False, False),
    ("video_1791909113811", 62, 84, 30, "scratch-move-left", True, False),
    ("video_1791909113811", 84, 144, 30, "scratch-right", False, False),
    ("video_1791909113811", 84, 144, 30, "scratch-left", True, False),
    ("video_1791909148857", 0, 289, 24, "lick-paw", False, False),
    ("video_1791909153731", 80, 280, 24, "idle", False, False),
    ("video_1791909166273", 0, 361, 24, "sleep", False, False),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    args = parser.parse_args()
    records = {}
    for source in dict.fromkeys(clip[0] for clip in CLIPS):
        paths = sorted((args.frames / source).glob("bug_*.png"))
        if not paths:
            raise ValueError(f"Missing decoded frames: {source}")
        selected = [clip for clip in CLIPS if clip[0] == source]
        indices = sorted({i for clip in selected for i in range(clip[1], clip[2])})
        frames = {i: key_blue(Image.open(paths[i])) for i in indices}
        boxes = [frame.getchannel("A").getbbox() for frame in frames.values()]
        if any(box is None for box in boxes):
            raise ValueError(f"Unexpected empty frame: {source}")
        left, top = min(b[0] for b in boxes), min(b[1] for b in boxes)
        right, bottom = max(b[2] for b in boxes), max(b[3] for b in boxes)
        side = max(right - left, bottom - top) + 20
        normalized = {}
        for i, frame in frames.items():
            canvas = Image.new("RGBA", (side, side))
            canvas.alpha_composite(frame.crop((left, top, right, bottom)),
                                   ((side - right + left) // 2, side - bottom + top - 10))
            normalized[i] = canvas
        del frames
        for _, start, end, fps, name, flip, reverse in selected:
            segment = [normalized[i] for i in range(start, end)]
            if reverse:
                segment.reverse()
            if flip:
                segment = [frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for frame in segment]
            output = ASSETS / f"cat-{name}.gif"
            write_gif(segment, output, fps)
            records[output.name] = dict(source=source + ".mp4", startFrame=start,
                                       endFrameExclusive=end, fps=fps, mirrored=flip,
                                       reversed=reverse, pixelsRescaled=False,
                                       canvas=[side, side], frames=len(segment),
                                       durationMs=round(len(segment) * 100 / fps) * 10)
    # The application prefers the -large paths for chase/pounce. Replace those
    # too; copying preserves the native pixels rather than enlarging a GIF.
    for name in ["chase-left", "chase-right", "chase-left-alt", "chase-right-alt",
                 "pounce-left", "pounce-right"]:
        source, target = f"cat-{name}.gif", f"cat-{name}-large.gif"
        shutil.copy2(ASSETS / source, ASSETS / target)
        records[target] = dict(records[source], aliasOf=source)
    for name in records:
        shutil.copy2(ASSETS / name, ASSETS / "cat-overlay-animations" / name)
    (ASSETS / "imported-videos/runtime-segments.json").write_text(
        json.dumps(records, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
