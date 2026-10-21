#!/usr/bin/env python3
"""Normalize blue-tinted ground shadows in the chase GIFs.

The source footage contains a navy shadow that is visible on dark desktop
themes.  Only opaque, blue-dominant pixels in the bottom shadow band are
changed; the cat, transparency, frame timing, and canvas geometry are kept.
"""
from pathlib import Path
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "apps/macos/Assets/Behavior"
TARGETS = tuple(
    f"{phase}-{direction}.gif"
    for phase in ("chase-enter", "catch", "chase-exit")
    for direction in ("left", "right")
)
SHADOW_Y_MIN = 850


def is_blue_shadow(r, g, b, a, y):
    return (
        a > 0
        and y >= SHADOW_Y_MIN
        and r <= 40
        and g <= 100
        and b >= g + 15
    )


def normalize_frame(frame):
    frame = frame.convert("RGBA")
    pixels = frame.load()
    changed = 0
    for y in range(SHADOW_Y_MIN, frame.height):
        for x in range(frame.width):
            red, green, blue, alpha = pixels[x, y]
            if is_blue_shadow(red, green, blue, alpha, y):
                pixels[x, y] = (0, 0, 0, alpha)
                changed += 1
    return frame, changed


def exact_palette(frame):
    """Encode a frame without quantizing unchanged visible RGB values."""
    rgba = frame.convert("RGBA")
    visible = []
    colors = {}
    pixels = list(rgba.getdata())
    for red, green, blue, alpha in pixels:
        color = (red, green, blue)
        if alpha > 0 and color not in colors:
            colors[color] = len(colors)
        visible.append(colors.get(color, 255) if alpha > 0 else 255)
    if len(colors) > 255:
        raise ValueError(f"GIF frame needs {len(colors)} visible colors")

    palette = [channel for color in colors for channel in color]
    result = Image.new("P", rgba.size, 255)
    result.putdata(visible)
    result.putpalette(palette + [0] * (768 - len(palette)))
    result.info["transparency"] = 255
    return result


def normalize(path):
    source = Image.open(path)
    frames = []
    durations = []
    changed = 0
    for index in range(source.n_frames):
        source.seek(index)
        frame, count = normalize_frame(source)
        changed += count
        frames.append(frame)
        durations.append(source.info.get("duration", 40))

    if not changed:
        return len(frames), 0
    encoded = [exact_palette(frame) for frame in frames]
    with tempfile.NamedTemporaryFile(suffix=".gif", dir=path.parent, delete=False) as temporary:
        output = Path(temporary.name)
    try:
        options = {
            "save_all": True,
            "append_images": encoded[1:],
            "duration": durations,
            "disposal": 2,
            "transparency": 255,
            "optimize": False,
        }
        if source.info.get("loop") == 0:
            options["loop"] = 0
        encoded[0].save(output, **options)

        written = Image.open(output)
        if written.n_frames != len(frames) or written.size != source.size:
            raise ValueError(f"{path.name}: GIF geometry changed")
        for index, expected in enumerate(frames):
            written.seek(index)
            if written.info.get("duration") != durations[index]:
                raise ValueError(f"{path.name}: timing changed at frame {index}")
            actual = written.convert("RGBA")
            for (red, green, blue, alpha), (actual_red, actual_green, actual_blue, actual_alpha) in zip(
                expected.getdata(), actual.getdata()
            ):
                if alpha != actual_alpha:
                    raise ValueError(f"{path.name}: transparency changed at frame {index}")
                if alpha > 0 and (red, green, blue) != (actual_red, actual_green, actual_blue):
                    raise ValueError(f"{path.name}: visible color changed at frame {index}")
        output.replace(path)
    finally:
        output.unlink(missing_ok=True)
    return len(frames), changed


def main():
    for name in TARGETS:
        path = ASSETS / name
        count, changed = normalize(path)
        print(f"{name}: normalized {changed} pixels across {count} frames", flush=True)


if __name__ == "__main__":
    main()
