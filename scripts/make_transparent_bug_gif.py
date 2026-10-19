#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image


def remove_white_background(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    arr = np.array(rgba).astype(np.float32)
    rgb = arr[:, :, :3]

    corners = np.concatenate(
        [
            rgb[:20, :20].reshape(-1, 3),
            rgb[:20, -20:].reshape(-1, 3),
            rgb[-20:, :20].reshape(-1, 3),
            rgb[-20:, -20:].reshape(-1, 3),
        ]
    )
    background = np.median(corners, axis=0)
    distance_from_background = np.sqrt(np.sum((rgb - background) ** 2, axis=2))
    brightness = np.mean(rgb, axis=2)

    # Estimate the video background from the four corners per frame. The source
    # is not pure white in every frame because of video compression, so fixed
    # white-keying leaves a dirty square. Bright pixels close to the estimated
    # background are fully removed; non-background insect pixels remain opaque.
    alpha = np.clip((distance_from_background - 32.0) / 72.0 * 255.0, 0, 255)
    alpha = np.where((brightness > 212.0) & (distance_from_background < 92.0), 0, alpha)
    arr[:, :, 3] = alpha

    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def content_bbox(frames: list[Image.Image]) -> tuple[int, int, int, int]:
    lefts: list[int] = []
    tops: list[int] = []
    rights: list[int] = []
    bottoms: list[int] = []
    for frame in frames:
        alpha = np.array(frame.getchannel("A"))
        ys, xs = np.where(alpha > 92)
        if len(xs) == 0 or len(ys) == 0:
            continue
        lefts.append(int(xs.min()))
        tops.append(int(ys.min()))
        rights.append(int(xs.max()) + 1)
        bottoms.append(int(ys.max()) + 1)

    if not lefts:
        width, height = frames[0].size
        return (0, 0, width, height)

    width, height = frames[0].size
    pad = 6
    return (
        max(0, min(lefts) - pad),
        max(0, min(tops) - pad),
        min(width, max(rights) + pad),
        min(height, max(bottoms) + pad),
    )


def quantize_for_gif(frame: Image.Image) -> Image.Image:
    # GIF transparency is palette-based. Reserving palette index 255 as
    # transparent gives VS Code a small animated asset with a clean background.
    rgba = frame.convert("RGBA")
    alpha = rgba.getchannel("A")
    opaque = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
    opaque.alpha_composite(rgba)
    paletted = opaque.convert("P", palette=Image.Palette.ADAPTIVE, colors=255)
    mask = alpha.point(lambda value: 255 if value <= 96 else 0)
    paletted.paste(255, mask)
    paletted.info["transparency"] = 255
    return paletted


def main() -> int:
    if len(sys.argv) < 4:
        print("usage: make_transparent_bug_gif.py <frames-dir> <output.gif> <frame-duration-ms> [target-px] [--flip-x]", file=sys.stderr)
        return 2

    frames_dir = Path(sys.argv[1])
    output = Path(sys.argv[2])
    duration_ms = int(sys.argv[3])
    target_px = int(sys.argv[4]) if len(sys.argv) >= 5 else 0
    flip_x = "--flip-x" in sys.argv[5:]

    paths = sorted(frames_dir.glob("bug_*.png"))
    if not paths:
        print(f"no frames found in {frames_dir}", file=sys.stderr)
        return 1

    transparent_frames = [remove_white_background(Image.open(path)) for path in paths]
    bbox = content_bbox(transparent_frames)
    cropped = [frame.crop(bbox) for frame in transparent_frames]

    # Normalize to a square transparent canvas so each frame keeps consistent
    # scale and does not jitter when rendered at 2ch in VS Code.
    max_side = max(max(frame.size) for frame in cropped)
    normalized: list[Image.Image] = []
    for frame in cropped:
        canvas = Image.new("RGBA", (max_side, max_side), (255, 255, 255, 0))
        canvas.alpha_composite(frame, ((max_side - frame.width) // 2, (max_side - frame.height) // 2))
        if target_px > 0:
            canvas = canvas.resize((target_px, target_px), Image.Resampling.LANCZOS)
        if flip_x:
            canvas = canvas.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        normalized.append(canvas)

    output.parent.mkdir(parents=True, exist_ok=True)
    gif_frames = [quantize_for_gif(frame) for frame in normalized]
    gif_frames[0].save(
        output,
        save_all=True,
        append_images=gif_frames[1:],
        optimize=False,
        duration=duration_ms,
        loop=0,
        disposal=2,
        transparency=255,
    )
    output_size = f"{target_px}x{target_px}" if target_px > 0 else f"{max_side}x{max_side}"
    flip_note = ", flipped-x" if flip_x else ""
    print(f"wrote {output} from {len(gif_frames)} frames, crop={bbox}, canvas={output_size}{flip_note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
