#!/usr/bin/env python3
"""Remove the snack wrapper from the native-resolution rubbish tail master."""
from collections import deque
from pathlib import Path
import argparse

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "media/behavior-masters/rubbish-tail.png"
ASSETS = ROOT / "apps/macos/Assets/Behavior"


def clean_frame(frame, outline_reference=None):
    rgba = np.asarray(frame.convert("RGBA"))
    red, green, blue, alpha = (rgba[:, :, channel].astype(np.int16) for channel in range(4))
    # The tail's orange fur has much more red than green; the wrapper is yellow.
    fur = ((red > green * 1.5) & (green > blue * 1.2) &
           (blue > 30) & (red > 90) & (green < 140) & (alpha > 127))
    ys, xs = np.nonzero(fur)
    visited = np.zeros(fur.shape, dtype=bool)
    largest = []
    for y, x in zip(ys, xs):
        if visited[y, x]:
            continue
        visited[y, x] = True
        queue = deque([(y, x)])
        component = []
        while queue:
            cy, cx = queue.popleft()
            component.append((cy, cx))
            for ny in range(max(0, cy - 1), min(fur.shape[0], cy + 2)):
                for nx in range(max(0, cx - 1), min(fur.shape[1], cx + 2)):
                    if fur[ny, nx] and not visited[ny, nx]:
                        visited[ny, nx] = True
                        queue.append((ny, nx))
        if len(component) > len(largest):
            largest = component
    if len(largest) < 1000:
        raise ValueError("Rubbish tail fur was not found")

    mask = np.zeros(fur.shape, dtype=np.uint8)
    for y, x in largest:
        mask[y, x] = 255
    # Nine native pixels retain the lower outline without reaching the wrapper.
    outline = Image.fromarray(mask).filter(ImageFilter.MaxFilter(19))
    outline_array = np.array(outline)
    bottom = np.full(fur.shape[1], -1, dtype=np.int16)
    body_y, body_x = np.nonzero(mask)
    np.maximum.at(bottom, body_x, body_y)
    neighbors = np.stack([np.roll(bottom, shift) for shift in range(-9, 10)])
    lower_edge = neighbors.max(axis=0) + 6
    outline_array[443:, :] *= (np.arange(443, fur.shape[0])[:, None] <= lower_edge[None, :])
    # The dark tail tip has no orange pixels to seed the mask. The wrapper only
    # reaches the lower part of these frames, so preserve the upper silhouette.
    outline_array[:443, :] = 255
    if outline_reference is not None:
        alpha = np.maximum(alpha, np.where(np.indices(alpha.shape)[0] < 443,
                                           outline_reference, 0))
    bright_wrapper = ((red > 230) & (green > 145) & (blue < 115))
    wrapper_y, wrapper_x = np.nonzero(bright_wrapper[515:, 760:806])
    for x in np.unique(wrapper_x):
        first = wrapper_y[wrapper_x == x].min() + 515
        outline_array[max(515, first - 2):, x + 760] = 0
    wrapper_color = ((red > green * 1.1) & (green > 140) & (blue < 120))
    outline_array[515:, :] *= ~wrapper_color[515:, :]
    cleaned = frame.convert("RGBA")
    cleaned.putalpha(Image.fromarray(np.minimum(alpha, outline_array).astype(np.uint8)))
    return cleaned


def encode(frames, path):
    frames = [frame.copy() for frame in frames]
    for index in range(3):
        frames[-3 + index] = Image.blend(frames[-3 + index], frames[0], (index + 1) / 3)
    encoded = []
    for frame in frames:
        rgb = Image.new("RGB", frame.size)
        rgb.paste(frame, mask=frame.getchannel("A"))
        palette = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
        palette.paste(255, frame.getchannel("A").point(lambda value: 255 if value < 128 else 0))
        encoded.append(palette)
    durations = [10 * (round((i + 1) * 100 / 24) - round(i * 100 / 24)) for i in range(len(frames))]
    encoded[0].save(path, save_all=True, append_images=encoded[1:], duration=durations,
                    loop=0, disposal=2, transparency=255, optimize=False)


def rebuild(outline_reference=None):
    reference = None
    if outline_reference is not None:
        with Image.open(outline_reference) as original:
            reference = []
            for index in range(original.n_frames):
                original.seek(index)
                reference.append(np.asarray(original.convert("RGBA").getchannel("A")))
    with Image.open(MASTER) as source:
        frames = []
        for index in range(source.n_frames):
            source.seek(index)
            frames.append(clean_frame(source.convert("RGBA"),
                                      None if reference is None else reference[index]))
    frames[0].save(MASTER, save_all=True, append_images=frames[1:], duration=1000 / 24,
                   loop=0, disposal=0, blend=0)
    encode(frames, ASSETS / "rubbish-tail-right.gif")
    encode([frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for frame in frames],
           ASSETS / "rubbish-tail-left.gif")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--restore-outline", type=Path)
    rebuild(parser.parse_args().restore_outline)
