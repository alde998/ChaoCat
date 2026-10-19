#!/usr/bin/env python3
"""Build native-resolution M02/M03 cat-only sprites from extracted video frames.

Extract media/chase-roll-sources/M02.mp4 and M03.mp4 with
extract_native_video_frames.swift, then pass the two frame directories here.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image
from key_blue_video_frames import key_blue
from refine_behavior_gifs import ASSETS, CATCH_FRAMES, encode_chase_frame, rewrite
from calibrate_behavior_layout import calibrate


def longest_run(mask):
    edges = np.diff(np.r_[False, mask, False].astype(int))
    starts, ends = np.where(edges == 1)[0], np.where(edges == -1)[0]
    index = np.argmax(ends - starts)
    return int(starts[index]), int(ends[index])


def normalize(path, remove_bug):
    frame = key_blue(Image.open(path))
    pixels = np.array(frame)
    if remove_bug:
        # The fly and its shadow are detached to the right of the cat. Follow
        # the largest silhouette rather than using a fixed crop through ears.
        columns = (pixels[:530, :, 3] > 0).any(axis=0)
        left, right = longest_run(columns)
        pixels[:, :max(0, left - 8), 3] = 0
        pixels[:, right + 8:, 3] = 0
    dark = (pixels[538:565, :, :3].max(axis=2) < 70) & (pixels[538:565, :, 3] > 0)
    left, right = longest_run(dark.any(axis=0))
    center = round((left + right) / 2)
    # Move pixels only, never rescale them. The ground shadow gives a stable
    # foot anchor while the actor controls the roll's desktop displacement.
    canvas = Image.new("RGBA", (1600, 1000))
    canvas.alpha_composite(Image.fromarray(pixels), (800 - center, 900 - 565))
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("m02", type=Path)
    parser.add_argument("m03", type=Path)
    args = parser.parse_args()
    catalog_path = ASSETS / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    for phase, directory, start, end, source in (
        ("chase-roll", args.m02, 34, 65, "M02.mp4"),
        ("chase-recover", args.m03, 0, 69, "M03.mp4"),
        ("chase", args.m03, 48, 68, "M03.mp4"),
    ):
        frames = [normalize(directory / f"bug_{i:05d}.png", source == "M02.mp4" and i <= 45)
                  for i in range(start, end)]
        if phase == "chase":
            # A full walking stride, with no seated startup or ghosted blend.
            # Source frames 48 and 67 are matching footfalls.
            frames[-1] = frames[0].copy()
        durations = [10 * (round((i + 1) * 100 / 24) - round(i * 100 / 24)) for i in range(len(frames))]
        for direction in ("right", "left"):
            name = f"{phase}-{direction}"
            selected = frames if direction == "right" else [f.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for f in frames]
            encoded = [encode_chase_frame(f) for f in selected]
            encoded[0].save(ASSETS / f"{name}.gif", save_all=True, append_images=encoded[1:],
                            duration=durations, transparency=255, disposal=2, optimize=False,
                            **({"loop": 0} if phase == "chase" else {}))
            catalog[name] = dict(file=f"{name}.gif", source=source, start=start, end=end,
                                 frames=len(frames), fps=24, duration=sum(durations)/1000,
                                 frameDurations=[d/1000 for d in durations], loop=phase == "chase", stride=0,
                                 width=1600, height=1000, footX=800, footY=900,
                                 scale=0.21503, mirrored=direction == "left")
            if phase == "chase":
                catalog[name]["stride"] = round(sum(durations)/1000 * 104, 2)
            if phase == "chase-recover":
                catalog[name]["motionStart"] = 28/24
                catalog[name]["stride"] = round((sum(durations)/1000 - 28/24) * 104, 2)
            print(name, len(frames), sum(durations)/1000, flush=True)
    for direction in ("right", "left"):
        name = f"catch-{direction}"
        if catalog[name].get("retainedFrames") != CATCH_FRAMES:
            # Save the exact pre-trim GIF for review/rollback. Rewriting uses
            # exact palettes, so retained frames lose no color or resolution.
            backup = ASSETS.parents[3] / "media/chase-roll-sources" / f"{name}-before-trim.gif"
            if not backup.exists():
                backup.write_bytes((ASSETS / f"{name}.gif").read_bytes())
            count, duration, _ = rewrite(name, keep=CATCH_FRAMES)
            image = Image.open(ASSETS / f"{name}.gif")
            delays = []
            for i in range(image.n_frames):
                image.seek(i)
                delays.append(image.info["duration"] / 1000)
            catalog[name].update(frames=count, duration=duration, frameDurations=delays,
                                 retainedFrames=CATCH_FRAMES)
    for phase in ("bug-fly", "bug-escape"):
        # The source insect looks LEFT (the original cat looks RIGHT).
        # Swap exact GIF bytes once; do not re-quantize the original insect.
        right,left=f"{phase}-right",f"{phase}-left"
        if not catalog[right].get("mirrored"):
            rp,lp=ASSETS/f"{right}.gif",ASSETS/f"{left}.gif"
            r,l=rp.read_bytes(),lp.read_bytes()
            rp.write_bytes(l);lp.write_bytes(r)
            catalog[right]["mirrored"]=True
            catalog[left]["mirrored"]=False
    calibrate(catalog)
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
