#!/usr/bin/env python3
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "apps/macos/Assets"
ARCHIVE_DIR = ASSET_DIR / "cat-overlay-animations"
CHASE_NAMES = [
  "chase-left", "chase-right", "chase-left-alt", "chase-right-alt",
  "pounce-left", "pounce-right",
]
CANVAS_SIZE = 156
TARGET_SCALE = 1.12
MARGIN = 2


def quantize(frame: Image.Image) -> Image.Image:
  rgba = frame.convert("RGBA")
  alpha = rgba.getchannel("A")
  composite = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
  composite.alpha_composite(rgba)
  paletted = composite.convert("P", palette=Image.Palette.ADAPTIVE, colors=255)
  transparent = alpha.point(lambda value: 255 if value <= 64 else 0)
  paletted.paste(255, transparent)
  paletted.info["transparency"] = 255
  return paletted


def enlarge_frame(frame: Image.Image) -> Image.Image:
  rgba = frame.convert("RGBA")
  bbox = rgba.getchannel("A").getbbox()
  if not bbox:
    return rgba

  left, top, right, bottom = bbox
  crop = rgba.crop(bbox)
  safe_scale = min(
    TARGET_SCALE,
    (CANVAS_SIZE - MARGIN * 2) / max(1, crop.width),
    (CANVAS_SIZE - MARGIN * 2) / max(1, crop.height),
  )
  size = (max(1, round(crop.width * safe_scale)), max(1, round(crop.height * safe_scale)))
  resized = crop.resize(size, Image.Resampling.LANCZOS)

  anchor_x = (left + right) / 2
  anchor_y = bottom
  x = round(anchor_x - resized.width / 2)
  y = round(anchor_y - resized.height)
  x = min(CANVAS_SIZE - MARGIN - resized.width, max(MARGIN, x))
  y = min(CANVAS_SIZE - MARGIN - resized.height, max(MARGIN, y))

  output = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
  output.alpha_composite(resized, (x, y))
  return output


def build(name: str) -> None:
  source = Image.open(ASSET_DIR / f"cat-{name}.gif")
  frames = []
  durations = []
  for index in range(source.n_frames):
    source.seek(index)
    frames.append(quantize(enlarge_frame(source)))
    durations.append(int(source.info.get("duration", 80)))

  for directory in [ASSET_DIR, ARCHIVE_DIR]:
    output = directory / f"cat-{name}-large.gif"
    frames[0].save(
      output,
      save_all=True,
      append_images=frames[1:],
      duration=durations,
      loop=0,
      disposal=2,
      transparency=255,
      optimize=False,
    )
    print(f"wrote {output}")


if __name__ == "__main__":
  for chase_name in CHASE_NAMES:
    build(chase_name)
