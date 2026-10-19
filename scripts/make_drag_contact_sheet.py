#!/usr/bin/env python3
"""Show extracted drag frames at their source times for segment review."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument("frames", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("fps", type=float)
args = parser.parse_args()

files = sorted(args.frames.glob("frame_*.png"))
columns, cell = 7, (230, 330)
sheet = Image.new("RGB", (columns * cell[0], ((len(files) + columns - 1) // columns) * cell[1]), "#e8ebed")
draw = ImageDraw.Draw(sheet)
for index, path in enumerate(files):
    frame = Image.open(path).convert("RGB")
    frame.thumbnail((cell[0] - 10, cell[1] - 32))
    x, y = (index % columns) * cell[0], (index // columns) * cell[1]
    sheet.paste(frame, (x + (cell[0] - frame.width) // 2, y + 3))
    draw.text((x + 8, y + cell[1] - 25), f"{index / args.fps:.2f}s", fill="#202326")
sheet.save(args.output)
