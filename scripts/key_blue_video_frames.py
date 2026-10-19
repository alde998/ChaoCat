#!/usr/bin/env python3
"""Key blue-screen PNG frames without spatial resampling; retain GIF timing."""
import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter, ImageMath


def key_blue(image):
    image = image.convert("RGB")
    r, g, b = [channel.convert("I") for channel in image.split()]
    background = ImageMath.lambda_eval(
        lambda a: ((a["b"] > 100) & (a["b"] - a["r"] > 35)
                   & (a["b"] - a["g"] > 15)) * 255,
        r=r, g=g, b=b,
    ).convert("L")
    # Neutralize blue contamination on dark anti-aliased outline pixels.
    blue = ImageMath.lambda_eval(
        lambda a: a["min"](a["b"], a["max"](a["r"], a["g"])),
        r=r, g=g, b=b,
    ).convert("L")
    alpha = background.point(lambda v: 255 - v)
    edge = ImageChops.subtract(alpha, alpha.filter(ImageFilter.MinFilter(5)))
    # Only remove spill at the keyed contour; keep interior fur/collar colors.
    blue = Image.composite(blue, b.convert("L"), edge)
    image = Image.merge("RGBA", (r.convert("L"), g.convert("L"), blue, alpha))
    return image


def quantize(image):
    rgb = image.convert("RGB")
    rgb.paste((0, 0, 0), image.getchannel("A").point(lambda v: 255 if v == 0 else 0))
    palette = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    palette.paste(255, image.getchannel("A").point(lambda v: 255 if v == 0 else 0))
    palette.info["transparency"] = 255
    return palette


def write_gif(frames, output, fps):
    # GIF delays are centiseconds: alternate 40/50 ms at 24 fps, rather
    # than rounding every frame to 40 ms and speeding the animation up.
    durations = [10 * (round((i + 1) * 100 / fps) - round(i * 100 / fps))
                 for i in range(len(frames))]
    encoded = [quantize(frame) for frame in frames]
    output.parent.mkdir(parents=True, exist_ok=True)
    encoded[0].save(output, save_all=True, append_images=encoded[1:],
                    duration=durations, loop=0, disposal=2,
                    transparency=255, optimize=False)
    print(f"{output}: {len(frames)} frames, {frames[0].size}, {sum(durations)} ms")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frames", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--fps", type=float, default=24)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--end", type=int)
    parser.add_argument("--square", action="store_true")
    parser.add_argument("--flip", action="store_true")
    args = parser.parse_args()
    paths = sorted(args.frames.glob("bug_*.png"))[args.start:args.end]
    if not paths:
        parser.error("No frames selected")
    frames = [key_blue(Image.open(path)) for path in paths]
    if args.square:
        boxes = [frame.getchannel("A").getbbox() for frame in frames]
        boxes = [box for box in boxes if box]
        if not boxes:
            parser.error("All frames are transparent")
        left, top = min(b[0] for b in boxes), min(b[1] for b in boxes)
        right, bottom = max(b[2] for b in boxes), max(b[3] for b in boxes)
        # Only discard transparent margins. Source subject pixels stay 1:1.
        side = max(right - left, bottom - top) + 20
        normalized = []
        for frame in frames:
            canvas = Image.new("RGBA", (side, side))
            canvas.alpha_composite(frame.crop((left, top, right, bottom)),
                                   ((side - right + left) // 2, side - bottom + top - 10))
            normalized.append(canvas)
        frames = normalized
    if args.flip:
        frames = [frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for frame in frames]
    write_gif(frames, args.output, args.fps)


if __name__ == "__main__":
    main()
