#!/usr/bin/env python3
"""Remove baked-in poop from the transparent behavior masters and rebuild GIFs."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
MASTERS = ROOT / "media/behavior-masters"
OUT = ROOT / "apps/macos/Assets/Behavior"


def position(frame, points):
    if frame <= points[0][0]:
        return points[0][1]
    for (left_frame, left_x), (right_frame, right_x) in zip(points, points[1:]):
        if frame <= right_frame:
            part = (frame - left_frame) / (right_frame - left_frame)
            return round(left_x + (right_x - left_x) * part)
    return points[-1][1]


def clean(frame, name, index, template):
    if name == "poop" and index < 52:
        return frame
    pixels = np.array(frame)
    if name == "poop":
        x = position(index, [(52, 372), (90, 372), (105, 245), (120, 175)])
        y = 695
    elif name == "bury-down":
        x = position(index, [(0, 1104), (7, 968), (14, 824), (21, 696), (28, 648), (42, 640), (57, 636)])
        y = 720
    else:
        x, y = 632, 720

    height, width = template.shape[:2]
    area = pixels[y:y + height, x:x + width]
    difference = np.abs(area[:, :, :3].astype(np.int16) - template[:, :, :3].astype(np.int16)).sum(axis=2)
    removal = (template[:, :, 3] > 20) & (difference < 300)
    if name == "bury-down" and index < 10:
        removal = template[:, :, 3] > 20
    if name == "poop":
        removal |= (template[:, :, 3] > 20) & (np.arange(width)[None, :] + x < 590)
    removal = np.asarray(Image.fromarray((removal * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
    area[:, :, 3] = np.where(removal, 0, area[:, :, 3])

    if name == "poop":
        # The moving ground shadow outlives the pile; keep the nearby tail.
        edge = 625 if index <= 58 else 600 if 100 <= index <= 112 else 500 if index < 100 else 400
        pixels[650:900, :edge, 3] = 0
        if index >= 100:
            pixels[720:900, :500, 3] = 0
    elif name == "bury-down" and index < 10:
        pixels[700:900, x + 10:x + width + 12, 3] = 0
    return Image.fromarray(pixels)


def encode(frames, path, fps):
    encoded = []
    for frame in frames:
        rgb = Image.new("RGB", frame.size)
        rgb.paste(frame, mask=frame.getchannel("A"))
        paletted = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
        paletted.paste(255, frame.getchannel("A").point(lambda value: 255 if value < 128 else 0))
        encoded.append(paletted)
    durations = [10 * (round((i + 1) * 100 / fps) - round(i * 100 / fps)) for i in range(len(frames))]
    encoded[0].save(path, save_all=True, append_images=encoded[1:], duration=durations,
                    disposal=2, transparency=255, optimize=False)


def save_local_image(frame):
    # The source crop cuts the right end of the ground shadow. Extend the
    # canvas and draw that shadow underneath the untouched subject pixels.
    crop = frame.crop((370, 690, 640, 895))
    pixels = np.array(crop)
    pixels[177:, :, 3] = 0
    pixels[155:, 255:, 3] = 0
    image = Image.new("RGBA", (300, 212))
    shadow = Image.new("RGBA", image.size)
    ImageDraw.Draw(shadow).ellipse((11, 165, 292, 207), fill=(0, 0, 0, 230))
    image.alpha_composite(shadow)
    image.alpha_composite(Image.fromarray(pixels), (12, 0))
    image.save(OUT / "poop.png")


def rebuild():
    poop_master = Image.open(MASTERS / "poop.png")
    poop_master.seek(66)
    reference = poop_master.convert("RGBA")
    template = np.asarray(reference.crop((372, 695, 625, 902))).astype(np.int16)
    save_local_image(reference)
    for name in ("poop", "bury-down", "bury"):
        master = Image.open(MASTERS / f"{name}.png")
        frames = []
        for index in range(master.n_frames):
            master.seek(index)
            frames.append(clean(master.convert("RGBA"), name, index, template))
        fps = 24 if name == "poop" else 30
        encode(frames, OUT / f"{name}-right.gif", fps)
        encode([frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for frame in frames],
               OUT / f"{name}-left.gif", fps)
        print(f"Cleaned {name}: {len(frames)} frames", flush=True)


if __name__ == "__main__":
    rebuild()
