#!/usr/bin/env python3
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image


def sample_border_color(image: Image.Image) -> tuple[int, int, int]:
  rgba = image.convert("RGBA")
  w, h = rgba.size
  pixels = rgba.load()
  samples: list[tuple[int, int, int]] = []
  band = max(2, min(w, h) // 18)

  for x in range(w):
    for y in range(band):
      samples.append(pixels[x, y][:3])
      samples.append(pixels[x, h - 1 - y][:3])

  for y in range(h):
    for x in range(band):
      samples.append(pixels[x, y][:3])
      samples.append(pixels[w - 1 - x, y][:3])

  if not samples:
    return (0, 255, 0)

  channels = list(zip(*samples))
  return tuple(sorted(channel)[len(channel) // 2] for channel in channels)  # type: ignore[return-value]


def remove_green_background(image: Image.Image, tolerance: int = 74) -> Image.Image:
  rgba = image.convert("RGBA")
  w, h = rgba.size
  pixels = rgba.load()
  background = sample_border_color(rgba)
  tolerance_sq = tolerance * tolerance

  def close_to_bg(x: int, y: int) -> bool:
    r, g, b, _ = pixels[x, y]
    dr = r - background[0]
    dg = g - background[1]
    db = b - background[2]
    return (dr * dr + dg * dg + db * db) <= tolerance_sq

  seen = bytearray(w * h)
  queue = deque()

  def idx(x: int, y: int) -> int:
    return y * w + x

  for x in range(w):
    for y in (0, h - 1):
      if close_to_bg(x, y):
        i = idx(x, y)
        if not seen[i]:
          seen[i] = 1
          queue.append((x, y))

  for y in range(h):
    for x in (0, w - 1):
      if close_to_bg(x, y):
        i = idx(x, y)
        if not seen[i]:
          seen[i] = 1
          queue.append((x, y))

  while queue:
    x, y = queue.popleft()
    pixels[x, y] = (255, 255, 255, 0)
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
      if nx < 0 or ny < 0 or nx >= w or ny >= h:
        continue
      i = idx(nx, ny)
      if seen[i]:
        continue
      seen[i] = 1
      if close_to_bg(nx, ny):
        queue.append((nx, ny))

  # Secondary cleanup for any interior green spill that is not connected to the edges.
  # These source videos were keyed with a saturated green screen, and some frames carry
  # isolated green residues after cropping/anti-aliasing. Remove them directly as well.
  for y in range(h):
    for x in range(w):
      r, g, b, a = pixels[x, y]
      if a == 0:
        continue
      if g >= 90 and g >= r + 24 and g >= b + 24:
        pixels[x, y] = (255, 255, 255, 0)

  return rgba


def crop_bbox(frames: list[Image.Image]) -> tuple[int, int, int, int]:
  left = top = 10**9
  right = bottom = -1

  for frame in frames:
    bbox = frame.getchannel("A").getbbox()
    if not bbox:
      continue
    l, t, r, b = bbox
    left = min(left, l)
    top = min(top, t)
    right = max(right, r)
    bottom = max(bottom, b)

  if right < 0:
    width, height = frames[0].size
    return (0, 0, width, height)

  pad = 8
  width, height = frames[0].size
  return (
    max(0, left - pad),
    max(0, top - pad),
    min(width, right + pad),
    min(height, bottom + pad),
  )


def quantize_for_gif(frame: Image.Image) -> Image.Image:
  rgba = frame.convert("RGBA")
  alpha = rgba.getchannel("A")
  composite = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
  composite.alpha_composite(rgba)
  paletted = composite.convert("P", palette=Image.Palette.ADAPTIVE, colors=255)
  mask = alpha.point(lambda value: 255 if value <= 64 else 0)
  paletted.paste(255, mask)
  paletted.info["transparency"] = 255
  return paletted


def main() -> int:
  if len(sys.argv) < 4:
    print(
      "usage: make_green_transparent_gif.py <frames-dir> <output.gif> <frame-duration-ms> [target-px] [--flip-x] [--start N] [--end N] [--bbox-from-all]",
      file=sys.stderr,
    )
    return 2

  frames_dir = Path(sys.argv[1])
  output = Path(sys.argv[2])
  duration_ms = int(sys.argv[3])
  target_px = int(sys.argv[4]) if len(sys.argv) >= 5 and sys.argv[4] != "--flip-x" else 0
  args = sys.argv[4:]
  flip_x = "--flip-x" in args
  bbox_from_all = "--bbox-from-all" in args
  start_index = 0
  end_index: int | None = None
  if "--start" in args:
    start_index = int(args[args.index("--start") + 1])
  if "--end" in args:
    end_index = int(args[args.index("--end") + 1])

  all_frame_paths = sorted(frames_dir.glob("bug_*.png"))
  frame_paths = all_frame_paths[start_index:end_index]
  if not frame_paths:
    print(f"no frames found in {frames_dir}", file=sys.stderr)
    return 1

  transparent_frames = [remove_green_background(Image.open(path)) for path in frame_paths]
  if bbox_from_all:
    bbox_source_frames = [remove_green_background(Image.open(path)) for path in all_frame_paths]
    bbox = crop_bbox(bbox_source_frames)
  else:
    bbox = crop_bbox(transparent_frames)
  cropped_frames = [frame.crop(bbox) for frame in transparent_frames]

  canvas_px = target_px if target_px > 0 else max(max(frame.size) for frame in cropped_frames)
  normalized: list[Image.Image] = []
  for frame in cropped_frames:
    scale = min(canvas_px / frame.width, canvas_px / frame.height)
    new_size = (max(1, round(frame.width * scale)), max(1, round(frame.height * scale)))
    resized = frame.resize(new_size, Image.Resampling.LANCZOS)
    if flip_x:
      resized = resized.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    canvas = Image.new("RGBA", (canvas_px, canvas_px), (255, 255, 255, 0))
    canvas.alpha_composite(resized, ((canvas_px - new_size[0]) // 2, canvas_px - new_size[1]))
    normalized.append(canvas)

  gif_frames = [quantize_for_gif(frame) for frame in normalized]
  output.parent.mkdir(parents=True, exist_ok=True)
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
  print(f"wrote {output} from {len(gif_frames)} frames, crop={bbox}, canvas={canvas_px}x{canvas_px}{', flipped-x' if flip_x else ''}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
