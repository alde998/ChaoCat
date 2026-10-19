#!/usr/bin/env python3
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
TARGETS = [
    ROOT / "apps/macos/Assets/cat-sleep.gif",
    ROOT / "apps/macos/Assets/cat-overlay-animations/cat-sleep.gif",
]


def make_round_trip(path: Path) -> None:
    with Image.open(path) as image:
        frames = []
        durations = []
        for index in range(image.n_frames):
            image.seek(index)
            frames.append(image.convert("RGBA"))
            durations.append(int(image.info.get("duration", 80)))

    if len(frames) == 143:
        return
    if len(frames) != 72:
        raise RuntimeError(f"Expected 72 source frames in {path}, found {len(frames)}")

    output_frames = frames + frames[-2::-1]
    output_durations = durations + durations[-2::-1]
    output_frames[0].save(
        path,
        save_all=True,
        append_images=output_frames[1:],
        duration=output_durations,
        loop=0,
        disposal=2,
        transparency=0,
        optimize=False,
    )


for target in TARGETS:
    make_round_trip(target)
