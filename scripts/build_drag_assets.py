#!/usr/bin/env python3
"""Key the supplied blue-screen drag video into native-resolution GIF clips."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "apps/macos/Assets/Behavior"
FPS = 24
SEGMENTS = (("drag-enter", 0, 23, False), ("drag", 23, 68, True), ("drag-exit", 68, 122, False))
BACKGROUND = np.array((3, 111, 232), dtype=np.float32)


def key(frame):
    rgb = np.asarray(frame.convert("RGB"), dtype=np.float32)
    # Blue-green chroma tracks the screen through compressed antialiased edges,
    # including the fine white whiskers and the dark ground shadow.
    alpha = np.clip((120 - (rgb[:, :, 2] - rgb[:, :, 1])) / 112, 0, 1)
    clean = np.clip((rgb - (1 - alpha[:, :, None]) * BACKGROUND) / np.maximum(alpha[:, :, None], 0.05), 0, 255)
    rgba = np.empty((*rgb.shape[:2], 4), dtype=np.uint8)
    rgba[:, :, :3] = clean.astype(np.uint8)
    rgba[:, :, 3] = np.rint(alpha * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def palette_for(frames):
    samples = [frames[i] for i in range(0, len(frames), 8)]
    montage = Image.new("RGB", (208 * len(samples), 278), "#ffffff")
    for index, frame in enumerate(samples):
        small = frame.resize((208, 278), Image.Resampling.LANCZOS)
        montage.paste(small, (index * 208, 0), small.getchannel("A"))
    palette = montage.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    colors = palette.getpalette()
    colors[255 * 3:256 * 3] = [255, 0, 255]
    palette.putpalette(colors)
    return palette


def encode(frames, destination, palette, loop):
    encoded = []
    for frame in frames:
        clean = Image.new("RGB", frame.size, "#ffffff")
        clean.paste(frame, mask=frame.getchannel("A"))
        indexed = clean.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG)
        indexed.paste(255, frame.getchannel("A").point(lambda value: 255 if value < 128 else 0))
        encoded.append(indexed)
    durations = [10 * (round((i + 1) * 100 / FPS) - round(i * 100 / FPS)) for i in range(len(encoded))]
    encoded[0].save(destination, save_all=True, append_images=encoded[1:], duration=durations,
                    **({"loop": 0} if loop else {}), disposal=2, transparency=255, optimize=False)
    # Pillow may coalesce identical indexed frames. The runtime catalog must
    # describe the written GIF, rather than the pre-quantized source list.
    written = Image.open(destination)
    written_durations = []
    for index in range(written.n_frames):
        written.seek(index)
        written_durations.append(written.info["duration"] / 1000)
    return written.n_frames, sum(written_durations), written_durations


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("frames", type=Path)
    args = parser.parse_args()
    paths = sorted(args.frames.glob("frame_*.png"))
    if len(paths) != 122:
        raise ValueError(f"Expected 122 source frames, found {len(paths)}")
    frames = [key(Image.open(path)) for path in paths]
    palette = palette_for(frames)
    catalog_path = OUT / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    for name, start, end, loop in SEGMENTS:
        segment = frames[start:end]
        for direction in ("right", "left"):
            mirrored = direction == "left"
            output = [frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for frame in segment] if mirrored else segment
            clip = f"{name}-{direction}"
            frame_count, duration, frame_durations = encode(output, OUT / f"{clip}.gif", palette, loop)
            catalog[clip] = {"file": f"{clip}.gif", "duration": duration, "frames": frame_count,
                             "fps": FPS, "frameDurations": frame_durations, "source": "drag-click-lift-drop.mp4",
                             "start": start, "end": end, "loop": loop, "stride": 0,
                             "width": 834, "height": 1112, "footX": 417, "footY": 1020,
                             "scale": 0.12, "mirrored": mirrored}
            print(f"{clip}: {len(output)} frames, {duration:.2f}s, {(OUT / f'{clip}.gif').stat().st_size / 1024 / 1024:.1f} MiB", flush=True)
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    preview = Image.new("RGB", (834, 1112 * 3), "#eef1f3")
    for row, index in enumerate((0, 40, 99)):
        frame = frames[index]
        preview.paste(frame, (0, row * 1112), frame.getchannel("A"))
    preview.save(ROOT / "docs/drag-segments-preview.png")


if __name__ == "__main__":
    main()
