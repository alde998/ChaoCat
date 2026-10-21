#!/usr/bin/env python3
"""Stabilize collar colors while preserving canvas, alpha and authored timing.

Requires numpy and Pillow. Each animation has an explicitly reviewed neck
region; only collar-colored components inside it are eligible for correction.
"""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np
from PIL import Image, ImageFilter, GifImagePlugin

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "apps/macos/Assets/Behavior"
REVIEW = ROOT / "exports/collar-audit"
COLLAR_COLORS = np.array(((108, 135, 99), (137, 169, 121), (160, 186, 136),
                          (174, 203, 151), (191, 213, 168)), dtype=np.uint8)
COLLAR_LUMA = np.array([0.299*r + 0.587*g + 0.114*b for r,g,b in COLLAR_COLORS])
# Neck landmarks in the existing, unscaled right-facing GIF canvases. Turning
# clips intentionally start facing left. Interpolation locates the collar;
# its actual outline is recovered independently in each frame.
TRACKS = {
    "walk": [(0,995,565),(1,995,565)],
    "turn-out": [(0,570,580),(.34,585,565),(.69,810,600),(1,970,565)],
    "turn-in": [(0,600,580),(.33,600,590),(.67,760,580),(1,960,565)],
    "run": [(0,1040,610),(1,1040,610)],
    "run-enter": [(0,980,570),(.67,980,555),(1,980,620)],
    "run-exit": [(0,980,620),(.33,980,555),(1,980,570)],
    "run-turn-in": [(0,550,615),(.33,645,645),(.67,810,670),(1,940,650)],
    "run-turn-out": [(0,630,630),(.33,570,650),(.67,815,695),(1,1030,660)],
    "sit-down": [(0,1000,580),(.33,995,595),(.67,910,585),(1,820,550)],
    "sit": [(0,860,550),(1,860,550)],
    "lick": [(0,835,555),(1,835,555)],
    "sit-up": [(0,820,550),(.33,820,550),(.67,920,580),(1,995,565)],
    "sleep-down": [(0,1025,565),(.33,1030,600),(.67,940,695),(1,955,740)],
    "sleep": [(0,940,765),(1,940,765)],
    "sleep-up": [(0,950,765),(.33,940,710),(.67,1015,610),(1,1010,565)],
    "poop": [(0,1030,570),(.33,1015,630),(.67,1000,585),(1,1035,570)],
    "bury-down": [(0,980,575),(.33,1000,570),(.67,970,560),(1,900,650)],
    "bury": [(0,900,650),(.65,900,650),(1,850,560)],
    "bury-up": [(0,925,550),(.33,940,550),(.67,1040,565),(1,1040,560)],
    "rubbish-discover": [(0,1030,560),(.33,965,580),(.67,955,555),(1,955,550)],
    "rubbish-run": [(0,1065,560),(.33,1065,590),(.67,1020,605),(1,1065,560)],
    "rubbish-jump": [(0,985,490),(1,1030,445)],
    "chase-enter": [(0,805,610),(.33,820,610),(.67,755,585),(1,720,660)],
    "chase": [(0,990,615),(.33,1045,615),(.67,985,625),(1,990,615)],
    "catch": [(0,825,640),(.33,860,555),(.67,835,675),(1,810,575)],
    "chase-exit": [(0,820,610),(1,795,605)],
    "drag": [(0,460,390),(1,460,390)],
    "drag-enter": [(0,460,460),(.33,460,530),(.67,460,355),(1,460,390)],
    "drag-exit": [(0,460,390),(.33,460,330),(.67,460,660),(1,460,460)],
    "chase-roll": [(0,1005,775),(.33,995,550),(.5,1000,735),(.67,680,785),(1,975,815)],
    "chase-recover": [(0,985,815),(.15,975,705),(.33,990,620),(.67,1000,610),(1,990,610)],
}


def candidate_mask(frame):
    rgba = np.asarray(frame.convert("RGBA"))
    red, green, blue = rgba[:, :, :3].astype(np.int16).transpose(2, 0, 1)
    return ((rgba[:, :, 3] > 0) & (red - green <= 38) & (green - red < 65)
            & (green - blue >= 2) & (green - blue < 75)
            & (green > 75) & (blue > 45) & (red < 245))


def components(mask, minimum=25):
    """Four-connected regions, with no additional image-processing dependency."""
    height, width = mask.shape
    stride = width + 2
    remaining = np.pad(mask, 1).ravel()
    result = []
    for first in np.flatnonzero(remaining):
        if not remaining[first]:
            continue
        remaining[first] = False
        pending = [int(first)]
        indices = []
        while pending:
            index = pending.pop()
            indices.append(index)
            for adjacent in (index - 1, index + 1, index - stride, index + stride):
                if remaining[adjacent]:
                    remaining[adjacent] = False
                    pending.append(adjacent)
        if len(indices) >= minimum:
            indices = np.array(indices)
            ys, xs = indices // stride - 1, indices % stride - 1
            result.append({"area": len(indices), "box": (int(xs.min()), int(ys.min()), int(xs.max()+1), int(ys.max()+1)),
                           "center": (float(xs.mean()), float(ys.mean())), "xs": xs, "ys": ys})
    return sorted(result, key=lambda region: region["area"], reverse=True)


def collar_mask(frame, phase, index, frame_count, left=False):
    if left:
        # Use one coordinate system, including component tie-breaking and
        # rounded crop edges, so exact source mirrors stay exact mirrors.
        return collar_mask(frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT),
                           phase, index, frame_count)[:, ::-1]
    fraction = index / max(1, frame_count-1)
    points = np.array(TRACKS[phase])
    x = float(np.interp(fraction, points[:,0], points[:,1]))
    y = float(np.interp(fraction, points[:,0], points[:,2]))
    radius = 120 if phase in ("drag-enter", "drag-exit", "chase-roll") else 95
    x1,x2 = max(0,round(x-radius)),min(frame.width,round(x+radius))
    y1,y2 = max(0,round(y-radius)),min(frame.height,round(y+radius))
    crop = frame.convert("RGBA").crop((x1,y1,x2,y2))
    candidates = Image.fromarray(candidate_mask(crop).astype(np.uint8)*255)
    # Fill single-pixel palette dithering inside the fabric before selecting
    # connected regions. The black outline and buckle are several pixels wide.
    closed = candidates.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    core = np.asarray(closed.filter(ImageFilter.MinFilter(3))) > 0
    regions = components(core)
    result = np.zeros((frame.height,frame.width),bool)
    if not regions:
        return result
    for region in regions:
        cx,cy=region["center"]
        distance=((cx+x1-x)**2+(cy+y1-y)**2)**.5
        region["score"] = region["area"] / (1+(distance/55)**2)
    main = max(regions,key=lambda region:region["score"])
    if main["area"] < 40:
        return result
    chosen = np.zeros(core.shape,bool)
    chosen[main["ys"],main["xs"]] = True
    # Include the buckle and the other half of a frontal collar, while keeping
    # detached whiskers, eyes and dust outside the correction.
    for _ in range(2):
        nearby = np.asarray(Image.fromarray(chosen.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(29))) > 0
        for region in regions:
            if nearby[region["ys"],region["xs"]].any():
                chosen[region["ys"],region["xs"]]=True
    expanded = np.asarray(Image.fromarray(chosen.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(3))) > 0
    # Closing is only for component discovery. Never paint over dark outline,
    # buckle or fur pixels that happened to lie in a filled one-pixel hole.
    result[y1:y2,x1:x2] = expanded & (np.asarray(candidates)>0)
    return result


def normalize_frame(frame, phase, index, frame_count, left=False):
    """Apply stable green shades only to the reviewed collar component."""
    rgba = np.asarray(frame.convert("RGBA")).copy()
    mask = collar_mask(frame, phase, index, frame_count, left=left)
    if not mask.any():
        return Image.fromarray(rgba, "RGBA"), 0
    red, green, blue = rgba[:, :, :3].astype(np.float32).transpose(2, 0, 1)
    luma = 0.299*red + 0.587*green + 0.114*blue
    nearest = np.abs(luma[mask, None] - COLLAR_LUMA[None, :]).argmin(axis=1)
    rgba[mask, :3] = COLLAR_COLORS[nearest]
    return Image.fromarray(rgba, "RGBA"), int(mask.sum())


def exact_palette(frame):
    rgba = np.asarray(frame.convert("RGBA"))
    visible = rgba[:, :, 3] > 0
    packed = (rgba[:, :, 0].astype(np.uint32) << 16) | (rgba[:, :, 1].astype(np.uint32) << 8) | rgba[:, :, 2]
    unique, counts = np.unique(packed[visible], return_counts=True)
    original_count = len(unique)
    if len(unique) > 255:
        # Reserve the collar shades and merge only the closest existing color
        # pairs when GIF's 255-visible-color limit is exceeded. Weight the
        # distance by pixel count to minimize color error, without resampling.
        colors = np.stack(((unique >> 16) & 255, (unique >> 8) & 255, unique & 255), axis=1).astype(np.int64)
        distances = np.sum((colors[:, None, :] - colors[None, :, :])**2, axis=2).astype(float)
        np.fill_diagonal(distances, np.inf)
        active = np.ones(len(unique), dtype=bool)
        protected = np.any(np.all(colors[:, None, :] == COLLAR_COLORS[None, :, :], axis=2), axis=1)
        weights = counts.copy()
        while active.sum() > 255:
            costs = distances * weights[:, None]
            costs[~active | protected, :] = np.inf
            costs[:, ~active] = np.inf
            removed, retained_index = np.unravel_index(costs.argmin(), costs.shape)
            active[removed] = False
            weights[retained_index] += weights[removed]
        retained = unique[active]
        palette_rgb = np.stack(((retained >> 16) & 255, (retained >> 8) & 255, retained & 255), axis=1).astype(np.int64)
        source_rgb = np.stack(((unique >> 16) & 255, (unique >> 8) & 255, unique & 255), axis=1).astype(np.int64)
        distances = np.sum((source_rgb[:, None, :] - palette_rgb[None, :, :])**2, axis=2)
        mapped = retained[np.argmin(distances, axis=1)]
        mapped_packed = packed.copy()
        mapped_packed[visible] = mapped[np.searchsorted(unique, packed[visible])]
        unique = retained
    else:
        mapped_packed = packed
    indexed = np.full(visible.shape, 255, dtype=np.uint8)
    indexed[visible] = np.searchsorted(unique, mapped_packed[visible]).astype(np.uint8)
    expected = rgba.copy()
    if original_count > len(unique):
        expected[:, :, 0][visible] = (mapped_packed[visible] >> 16).astype(np.uint8)
        expected[:, :, 1][visible] = ((mapped_packed[visible] >> 8) & 255).astype(np.uint8)
        expected[:, :, 2][visible] = (mapped_packed[visible] & 255).astype(np.uint8)
    result = Image.fromarray(indexed, "P")
    palette = [channel for color in unique for channel in (int(color >> 16), int((color >> 8) & 255), int(color & 255))]
    result.putpalette(palette + [0] * (768 - len(palette)))
    result.info["transparency"] = 255
    return result, Image.fromarray(expected, "RGBA")


def visible_digest(frame):
    rgba = np.asarray(frame.convert("RGBA"))
    return (hashlib.sha256(rgba[:, :, 3].tobytes()).digest(),
            hashlib.sha256(rgba[:, :, :3][rgba[:, :, 3] > 0].tobytes()).digest())


def rewrite_assets(only=None, direction_filter=None):
    catalog = json.loads((ASSETS / "catalog.json").read_text())
    processed = set()
    for name, clip in catalog.items():
        if not (name.endswith("-right") or name.endswith("-left")):
            continue
        direction = "left" if name.endswith("-left") else "right"
        if direction_filter and direction != direction_filter:
            continue
        phase = name[:-5] if direction == "left" else name[:-6]
        if phase not in TRACKS:
            continue
        if only and phase not in only:
            continue
        destination = ASSETS / clip["file"]
        key = str(destination)
        if key in processed:
            continue
        processed.add(key)
        source = Image.open(destination)
        frame_count = source.n_frames
        durations, expected_digests, changed = [], [], 0
        info = {"transparency": 255, "background": 255, "optimize": False}
        if "loop" in source.info:
            info["loop"] = source.info["loop"]
        temporary = destination.with_suffix(".collar.tmp.gif")
        try:
            # Stream individual GIF image blocks. This keeps duplicate frames
            # and avoids holding hundreds of full-resolution RGBA frames.
            with temporary.open("wb") as output:
                for index in range(frame_count):
                    source.seek(index)
                    frame, count = normalize_frame(source, phase, index, frame_count, left=direction == "left")
                    encoded, expected = exact_palette(frame)
                    changed += count
                    duration = source.info.get("duration", 40)
                    durations.append(duration)
                    expected_digests.append(visible_digest(expected))
                    if index == 0:
                        for block in GifImagePlugin.getheader(encoded, info=info)[0]:
                            output.write(block)
                    # ImageIO can reject long animations made entirely of
                    # cropped subframes (the 252-frame poop clip is affected).
                    # Full-canvas image blocks retain native decoder support.
                    box = ((0, 0, source.width, source.height) if frame_count > 128
                           else expected.getchannel("A").getbbox())
                    for block in GifImagePlugin.getdata(encoded.crop(box), offset=box[:2], duration=duration,
                                                        disposal=2, transparency=255, include_color_table=True):
                        output.write(block)
                output.write(b";")
            written = Image.open(temporary)
            if written.n_frames != frame_count or written.size != source.size:
                raise ValueError(f"{destination.name}: encoder changed frame count or canvas")
            if written.info.get("loop") != info.get("loop"):
                raise ValueError(f"{destination.name}: encoder changed looping")
            for index, digest in enumerate(expected_digests):
                written.seek(index)
                if (written.info.get("duration") != durations[index]
                        or visible_digest(written) != digest):
                    raise ValueError(f"{destination.name}: frame {index} changed outside collar normalization")
            written.close()
            source.close()
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
        print(f"{destination.name}: normalized {changed} collar pixels across {frame_count} frames", flush=True)


def audit():
    REVIEW.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((ASSETS / "catalog.json").read_text())
    report = {}
    for name, clip in catalog.items():
        if not name.endswith("-right") or name.startswith(("bug-", "chase-run-", "rubbish-tail-")):
            continue
        source = Image.open(ASSETS / clip["file"])
        sample_indices = sorted(set([0, source.n_frames//3, source.n_frames*2//3, source.n_frames-1]))
        entries = []
        for index in sample_indices:
            source.seek(index)
            mask = Image.fromarray(candidate_mask(source).astype(np.uint8)*255).filter(ImageFilter.MinFilter(3))
            regions = components(np.asarray(mask) > 0)
            entries.append({"frame": index, "regions": [{k: r[k] for k in ("area", "box", "center")} for r in regions[:6]]})
        report[name] = entries
        print(name, [(entry["frame"], [(r["area"], r["box"]) for r in entry["regions"][:3]]) for entry in entries], flush=True)
    (REVIEW / "components.json").write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--rewrite", action="store_true")
    parser.add_argument("--only", nargs="+")
    parser.add_argument("--direction", choices=("left", "right"))
    args = parser.parse_args()
    if args.rewrite:
        rewrite_assets(only=args.only, direction_filter=args.direction)
    else:
        audit()
