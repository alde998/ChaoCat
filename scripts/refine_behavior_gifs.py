#!/usr/bin/env python3
"""Trim the rubbish takeoff and clear fly-trail pixels from cat-only GIFs."""
import json
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from calibrate_behavior_layout import calibrate
from normalize_chase_shadows import normalize_frame

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "apps/macos/Assets/Behavior"
CHASE_NAMES = ("chase-enter", "chase", "catch", "chase-exit")
# One complete crouch / pounce / landing. Frames 24–28 have ears cut at y=300.
CATCH_FRAMES = [*range(20, 24), *range(29, 41)]
MASTERS = ROOT / "media/behavior-masters"
COLLAR_COLORS = np.array(((160, 186, 136), (174, 203, 151), (191, 213, 168)), dtype=np.uint8)


def remove_chase_bleed(frame):
    rgba = np.array(frame.convert("RGBA"))
    red, green, blue = (rgba[:, :, channel].astype(np.int16) for channel in range(3))
    visible = rgba[:, :, 3] > 0
    # The flight arc is pale cyan; the cat's collar is green with much less blue.
    bleed = visible & (red >= 100) & (green > red + 8) & (blue > red + 8) & (abs(green - blue) <= 30)
    rgba[bleed, 3] = 0
    # Keep future rebuilds consistent with the neutral ground shadow used by
    # the shipping GIFs, including on a dark desktop background.
    cleaned, _ = normalize_frame(Image.fromarray(rgba, "RGBA"))
    return cleaned, int(bleed.sum())


def encode_chase_frame(frame, collar_region=None):
    rgba = np.asarray(frame.convert("RGBA"))
    visible = rgba[:, :, 3] >= 128
    red, green, blue = (rgba[:, :, channel].astype(np.int16) for channel in range(3))
    if collar_region is None:
        collar = visible & (green > red + 8) & (green > blue + 20) & (blue < red) & (red > 120) & (red < 220)
    else:
        x1, y1, x2, y2 = collar_region
        collar = np.zeros(visible.shape, dtype=bool)
        collar[y1:y2, x1:x2] = (
            visible[y1:y2, x1:x2]
            & (green[y1:y2, x1:x2] > red[y1:y2, x1:x2] + 5)
            & (green[y1:y2, x1:x2] > blue[y1:y2, x1:x2] + 8)
            & (red[y1:y2, x1:x2] > 50)
        )
    rgb = Image.new("RGB", frame.size)
    rgb.paste(frame, mask=frame.getchannel("A"))
    quantized = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    pixels = np.array(quantized)
    palette = np.zeros((256, 3), dtype=np.uint8)
    source_palette = np.array(quantized.getpalette(), dtype=np.uint8).reshape(-1, 3)
    palette[:len(source_palette)] = source_palette

    # Reuse the least-used palette entries so the rest of the cat keeps its original quantization.
    counts = np.bincount(pixels[visible & ~collar], minlength=256)
    reserved = np.argsort(counts[:255], kind="stable")[:len(COLLAR_COLORS)]
    available = np.setdiff1d(np.arange(255), reserved)
    for index in reserved:
        if counts[index]:
            difference = palette[available].astype(np.int32) - palette[index].astype(np.int32)
            nearest = available[np.argmin(np.sum(difference * difference, axis=1))]
            pixels[(pixels == index) & visible & ~collar] = nearest
    if collar.any():
        difference = rgba[collar, :3].astype(np.int32)[:, None] - COLLAR_COLORS.astype(np.int32)[None]
        pixels[collar] = reserved[np.argmin(np.sum(difference * difference, axis=2), axis=1)]
    pixels[~visible] = 255
    palette[reserved] = COLLAR_COLORS
    result = Image.fromarray(pixels, "P")
    result.putpalette(palette.flatten().tolist())
    return result


def exact_palette(frame):
    rgba = np.asarray(frame.convert("RGBA"))
    visible = rgba[:, :, 3] > 0
    colors = rgba[:, :, :3].astype(np.uint32)
    packed = (colors[:, :, 0] << 16) | (colors[:, :, 1] << 8) | colors[:, :, 2]
    unique = np.unique(packed[visible])
    if len(unique) > 255:
        raise ValueError(f"GIF frame needs {len(unique)} visible colors")
    indexed = np.full(visible.shape, 255, dtype=np.uint8)
    indexed[visible] = np.searchsorted(unique, packed[visible]).astype(np.uint8)
    result = Image.fromarray(indexed, "P")
    palette = [channel for color in unique for channel in (int(color >> 16), int((color >> 8) & 255), int(color & 255))]
    result.putpalette(palette + [0] * (768 - len(palette)))
    result.info["transparency"] = 255
    return result


def rewrite(name, keep=None, cleaner=None, last_duration=None):
    destination = ASSETS / f"{name}.gif"
    source = Image.open(destination)
    indices = list(range(source.n_frames)) if keep is None or source.n_frames == len(keep) else list(keep)
    loops = source.info.get("loop") == 0
    expected, durations, removed = [], [], 0
    for index in indices:
        # A previous refinement may already have removed the duplicate tail;
        # recreate the required loop-closing first pose when upgrading that
        # older asset in place.
        source.seek(index if index < source.n_frames else 0)
        frame = source.convert("RGBA")
        if cleaner:
            frame, count = cleaner(frame)
            removed += count
        expected.append(frame)
        durations.append(source.info["duration"] if index < source.n_frames else 10)
    if last_duration is not None:
        durations[-1] = last_duration
    encoded = [exact_palette(frame) for frame in expected]
    with tempfile.NamedTemporaryFile(suffix=".gif", dir=ASSETS, delete=False) as temporary:
        output = Path(temporary.name)
    try:
        options = {"save_all": True, "append_images": encoded[1:], "duration": durations,
                   "disposal": 2, "transparency": 255, "optimize": False}
        if loops:
            options["loop"] = 0
        encoded[0].save(output, **options)
        written = Image.open(output)
        if written.n_frames != len(expected):
            raise ValueError(f"{name}: frame count changed")
        for index, frame in enumerate(expected):
            written.seek(index)
            actual = np.asarray(written.convert("RGBA"))
            wanted = np.asarray(frame)
            if written.info["duration"] != durations[index] or not np.array_equal(actual[:, :, 3], wanted[:, :, 3]):
                raise ValueError(f"{name}: timing or transparency changed at frame {index}")
            visible = wanted[:, :, 3] > 0
            if not np.array_equal(actual[:, :, :3][visible], wanted[:, :, :3][visible]):
                raise ValueError(f"{name}: visible colors changed at frame {index}")
        output.replace(destination)
    finally:
        output.unlink(missing_ok=True)
    return len(expected), sum(durations) / 1000, removed


def restore_chase(name, phase, direction, fps, loop):
    master = Image.open(MASTERS / f"{phase}.png")
    frames = []
    removed = 0
    for index in (CATCH_FRAMES if phase == "catch" else range(master.n_frames)):
        master.seek(index)
        frame = master.convert("RGBA")
        if direction == "left":
            frame = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        frame, count = remove_chase_bleed(frame)
        frames.append(frame)
        removed += count
    if loop and len(frames) > 8:
        for index in range(3):
            frames[-3 + index] = Image.blend(frames[-3 + index], frames[0], (index + 1) / 3)

    encoded = [encode_chase_frame(frame) for frame in frames]
    durations = [10 * (round((index + 1) * 100 / fps) - round(index * 100 / fps))
                 for index in range(len(frames))]
    destination = ASSETS / f"{name}.gif"
    with tempfile.NamedTemporaryFile(suffix=".gif", dir=ASSETS, delete=False) as temporary:
        output = Path(temporary.name)
    try:
        encoded[0].save(output, save_all=True, append_images=encoded[1:], duration=durations,
                        disposal=2, transparency=255, optimize=False, **({"loop": 0} if loop else {}))
        result = Image.open(output)
        if result.n_frames != len(frames):
            raise ValueError(f"{name}: frame count changed")
        for index, duration in enumerate(durations):
            result.seek(index)
            if result.info["duration"] != duration:
                raise ValueError(f"{name}: timing changed at frame {index}")
        output.replace(destination)
    finally:
        output.unlink(missing_ok=True)
    return len(frames), sum(durations) / 1000, removed


def restore_sleep(direction):
    source = Image.open(MASTERS / "sleep.png")
    frames = []
    for index in range(source.n_frames):
        source.seek(index)
        frame = source.convert("RGBA")
        if direction == "left":
            frame = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        frames.append(frame)
    if len(frames) < 95:
        frames += frames[-2::-1]
    durations = [10 * (round((index + 1) * 100 / 24) - round(index * 100 / 24))
                 for index in range(len(frames))]
    encoded = []
    for frame in frames:
        # The sleeping cat's collar occupies a small area and otherwise gets
        # merged into the brown fur by GIF quantization. Reserve the same
        # green palette entries used by the chase clips for that region.
        collar_region = (620, 690, 710, 850) if direction == "left" else (890, 690, 980, 850)
        encoded.append(encode_chase_frame(frame, collar_region=collar_region))
    destination = ASSETS / f"sleep-{direction}.gif"
    with tempfile.NamedTemporaryFile(suffix=".gif", dir=ASSETS, delete=False) as temporary:
        output = Path(temporary.name)
    try:
        encoded[0].save(output, save_all=True, append_images=encoded[1:], duration=durations,
                        disposal=2, transparency=255, optimize=False, loop=0)
        output.replace(destination)
    finally:
        output.unlink(missing_ok=True)
    return len(frames), sum(durations) / 1000


def main():
    catalog_path = ASSETS / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    for direction in ("right", "left"):
        lick_name = f"lick-{direction}"
        # The authored lick clip ends with two copies of its first pose. At a
        # loop boundary those frames become a visible static hold, so keep one
        # loop-closing copy and shorten its display time.
        # The user's 58-frame edit ends seated and is repeated by the
        # controller. Do not restore the removed raised-paw closing frames.
        if catalog[lick_name]["loop"] and catalog[lick_name]["frames"] != 60:
            count, duration, _ = rewrite(lick_name, keep=range(60), last_duration=10)
            catalog[lick_name].update(frames=count, duration=duration)
        sleep_frames, sleep_duration = restore_sleep(direction)
        catalog[f"sleep-{direction}"].update(frames=sleep_frames, duration=sleep_duration)
        name = f"rubbish-jump-{direction}"
        if catalog[name]["frames"] != 8:
            count, duration, _ = rewrite(name, keep=range(10, 18))
            catalog[name].update(start=152, frames=count, duration=duration)
        for phase in CHASE_NAMES:
            name = f"{phase}-{direction}"
            if phase == "chase" and catalog[name].get("source") == "M03.mp4":
                continue  # Keep the true walking cycle, not the old seated startup.
            count, duration, removed = restore_chase(name, phase, direction, 24, phase == "chase")
            catalog[name].update(frames=count, duration=duration, scale=0.2094)
            if phase == "catch":
                catalog[name]["retainedFrames"] = CATCH_FRAMES
                catalog[name]["frameDurations"] = [
                    (round((i + 1) * 100 / 24) - round(i * 100 / 24)) / 100
                    for i in range(count)]
            if phase == "chase":
                catalog[name]["stride"] = round(142 * 0.2094 / 0.18, 2)
            print(f"{name}: cleared {removed} trail pixels", flush=True)
    calibrate(catalog)
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    from normalize_collar_colors import rewrite_assets
    rewrite_assets()


if __name__ == "__main__":
    main()
