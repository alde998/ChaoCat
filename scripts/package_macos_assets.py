#!/usr/bin/env python3
"""Package only runtime assets, sharing *exact* mirrored GIFs without re-encoding.

Requires Pillow. Original editable GIFs/catalog remain untouched.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'apps/macos/Assets'
CACHE = ROOT / 'apps/macos/.build/asset-verification.json'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exact_mirror(right, left):
    with Image.open(right) as r, Image.open(left) as l:
        if r.size != l.size or r.n_frames != l.n_frames or r.info.get('loop') != l.info.get('loop'):
            return False
        for index in range(r.n_frames):
            r.seek(index); l.seek(index)
            if r.info.get('duration') != l.info.get('duration'):
                return False
            a = r.convert('RGBA').transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            b = l.convert('RGBA')
            # Compare alpha and all visible RGB, ignoring hidden transparent RGB.
            if a.getchannel('A').tobytes() != b.getchannel('A').tobytes():
                return False
            background = Image.new('RGBA', r.size, (0, 0, 0, 255))
            if Image.alpha_composite(background, a).tobytes() != Image.alpha_composite(background, b).tobytes():
                return False
        return True


def package(destination):
    behavior = ASSETS / 'Behavior'
    catalog = json.loads((behavior / 'catalog.json').read_text())
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    original_files = {c['file'] for c in catalog.values()}
    shared = []
    for name, clip in catalog.items():
        if not name.endswith('-left'):
            continue
        right = catalog.get(name[:-5] + '-right')
        if not right:
            continue
        left_path, right_path = behavior / clip['file'], behavior / right['file']
        key = 'mirror-v1:' + digest(left_path) + ':' + digest(right_path)
        if key not in cache:
            cache[key] = exact_mirror(right_path, left_path)
            CACHE.parent.mkdir(parents=True, exist_ok=True)
            CACHE.write_text(json.dumps(cache, indent=2) + '\n')
        if cache[key]:
            shared.append(name)
            clip['file'] = right['file']
            clip['mirrorX'] = True
    out = destination / 'Assets/Behavior'
    out.mkdir(parents=True, exist_ok=True)
    runtime_files = {c['file'] for c in catalog.values()}
    for name in sorted(runtime_files | {'poop.png', 'rubbish.png', 'rubbish-left.png'}):
        shutil.copy2(behavior / name, out / name)
    (out / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')) + '\n')
    for name in ('StatusIcon.png', 'CleanupPhoto.jpg'):
        shutil.copy2(ASSETS / name, destination / 'Assets' / name)
    shutil.copy2(ASSETS / 'AppIcon.icns', destination / 'AppIcon.icns')
    # Keep the bridge and shared protocol available to bundled integrations.
    for relative in ('apps/bridge', 'shared'):
        shutil.copytree(ROOT / relative, destination / relative,
                        ignore=shutil.ignore_patterns('.DS_Store', '__pycache__', '*.map'), dirs_exist_ok=True)
    report = {
        'sourceGIFBytes': sum((behavior / p).stat().st_size for p in original_files),
        'packagedGIFBytes': sum((behavior / p).stat().st_size for p in runtime_files),
        'sourceGIFFiles': len(original_files), 'packagedGIFFiles': len(runtime_files),
        'exactMirrorClips': shared,
        'quality': 'Original GIF bytes; same decoded pixels, dimensions, frames, timing and palettes. Mirror only after every frame matches.',
    }
    report_path = ROOT / 'exports/package-optimization/assets.json'
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path, help='App Contents/Resources directory')
    package(parser.parse_args().destination)
