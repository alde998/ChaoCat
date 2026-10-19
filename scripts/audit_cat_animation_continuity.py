#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ANIMATION_DIR = ROOT / "apps/macos/Assets/cat-overlay-animations"
MANIFEST_PATH = ANIMATION_DIR / "animation-manifest.json"
REPORT_PATH = ANIMATION_DIR / "CONTINUITY_REPORT.md"
SHEET_PATH = Path("/private/tmp/cat-continuity-contact-sheet.jpg")


@dataclass
class FrameMetrics:
  bbox: tuple[int, int, int, int] | None
  width: int
  height: int
  anchor_x: float
  anchor_y: float


def frame_metrics(frame: Image.Image) -> FrameMetrics:
  rgba = frame.convert("RGBA")
  bbox = rgba.getchannel("A").getbbox()
  if not bbox:
    return FrameMetrics(None, 0, 0, 0, 0)
  left, top, right, bottom = bbox
  width = right - left
  height = bottom - top
  return FrameMetrics(bbox, width, height, left + width / 2, bottom)


def read_frames(path: Path) -> tuple[list[Image.Image], list[int]]:
  image = Image.open(path)
  frames: list[Image.Image] = []
  durations: list[int] = []
  for index in range(getattr(image, "n_frames", 1)):
    image.seek(index)
    frames.append(image.convert("RGBA"))
    durations.append(int(image.info.get("duration", 80)))
  return frames, durations


def metric_ratio(a: FrameMetrics, b: FrameMetrics) -> tuple[float, float]:
  width_ratio = b.width / a.width if a.width else 0
  height_ratio = b.height / a.height if a.height else 0
  return width_ratio, height_ratio


def anchor_distance(a: FrameMetrics, b: FrameMetrics) -> float:
  return math.hypot(b.anchor_x - a.anchor_x, b.anchor_y - a.anchor_y)


def continuity_grade(segment: dict[str, Any], first: FrameMetrics, last: FrameMetrics) -> str:
  if not segment.get("loopable"):
    return "n/a"
  width_ratio, height_ratio = metric_ratio(first, last)
  anchor_delta = anchor_distance(first, last)
  if abs(width_ratio - 1) <= 0.08 and abs(height_ratio - 1) <= 0.08 and anchor_delta <= 10:
    return "pass"
  if abs(width_ratio - 1) <= 0.18 and abs(height_ratio - 1) <= 0.18 and anchor_delta <= 22:
    return "watch"
  return "needs-fix"


def make_contact_sheet(rows: list[dict[str, Any]]) -> None:
  cell_w = 300
  cell_h = 148
  sheet = Image.new("RGB", (cell_w * 2, cell_h * len(rows)), "white")

  for row_index, row in enumerate(rows):
    for side, key in enumerate(["firstFrame", "lastFrame"]):
      frame = row[key]
      metrics: FrameMetrics = row["first"] if side == 0 else row["last"]
      canvas = Image.new("RGBA", (cell_w, cell_h), (246, 246, 246, 255))
      crop = frame.crop(metrics.bbox) if metrics.bbox else frame
      crop.thumbnail((190, 104), Image.Resampling.LANCZOS)
      canvas.alpha_composite(crop, ((cell_w - crop.width) // 2, 34 + (96 - crop.height) // 2))
      draw = ImageDraw.Draw(canvas)
      label = "first" if side == 0 else "last"
      draw.text((8, 6), f"{row['id']} / {label}", fill=(0, 0, 0))
      draw.text((8, 20), f"{metrics.width}x{metrics.height} anchor=({metrics.anchor_x:.0f},{metrics.anchor_y:.0f})", fill=(70, 70, 70))
      sheet.paste(canvas.convert("RGB"), (cell_w * side, cell_h * row_index))

  SHEET_PATH.parent.mkdir(parents=True, exist_ok=True)
  sheet.save(SHEET_PATH, quality=92)


def main() -> int:
  manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
  segments: list[dict[str, Any]] = manifest["segments"]
  by_id = {segment["id"]: segment for segment in segments}

  rows: list[dict[str, Any]] = []
  missing: list[str] = []
  for segment in segments:
    path = ANIMATION_DIR / segment["file"]
    if not path.exists():
      missing.append(segment["file"])
      continue
    frames, durations = read_frames(path)
    first = frame_metrics(frames[0])
    last = frame_metrics(frames[-1])
    width_ratio, height_ratio = metric_ratio(first, last)
    rows.append({
      "id": segment["id"],
      "file": segment["file"],
      "role": segment["role"],
      "loopable": segment.get("loopable", False),
      "movesWindow": segment.get("movesWindow", False),
      "frames": len(frames),
      "duration": sum(durations) / 1000,
      "first": first,
      "last": last,
      "widthRatio": width_ratio,
      "heightRatio": height_ratio,
      "anchorDelta": anchor_distance(first, last),
      "grade": continuity_grade(segment, first, last),
      "firstFrame": frames[0],
      "lastFrame": frames[-1],
    })

  transition_rows: list[tuple[str, str, str]] = []
  for source_id, target_id in manifest.get("allowedTransitions", []):
    source = by_id.get(source_id)
    target = by_id.get(target_id)
    if not source or not target:
      transition_rows.append((source_id, target_id, "missing segment id"))
      continue
    if source["toPose"] == target["fromPose"]:
      status = "pass"
    else:
      status = f"watch: {source['toPose']} -> {target['fromPose']}"
    transition_rows.append((source_id, target_id, status))

  make_contact_sheet(rows)

  lines = [
    "# Cat Animation Continuity Report\n\n",
    "这份报告用于检查猫浮层动画是否像同一只猫在连续运动，而不是多个 GIF 硬切。\n\n",
    f"- Contact sheet: `{SHEET_PATH}`\n",
    f"- Missing files: {', '.join(missing) if missing else 'none'}\n\n",
    "## Segment continuity\n\n",
    "| id | file | role | frames | duration | first | last | ratio | anchor Δ | loop grade |\n",
    "|---|---|---|---:|---:|---:|---:|---:|---:|---|\n",
  ]
  for row in rows:
    lines.append(
      f"| `{row['id']}` | `{row['file']}` | {row['role']} | {row['frames']} | {row['duration']:.2f}s | "
      f"{row['first'].width}x{row['first'].height} | {row['last'].width}x{row['last'].height} | "
      f"{row['widthRatio']:.2f}/{row['heightRatio']:.2f} | {row['anchorDelta']:.1f}px | {row['grade']} |\n"
    )

  lines.extend([
    "\n## Allowed transition pose checks\n\n",
    "| from | to | status |\n",
    "|---|---|---|\n",
  ])
  for source_id, target_id, status in transition_rows:
    lines.append(f"| `{source_id}` | `{target_id}` | {status} |\n")

  REPORT_PATH.write_text("".join(lines), encoding="utf-8")
  print(f"wrote {REPORT_PATH}")
  print(f"wrote {SHEET_PATH}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
