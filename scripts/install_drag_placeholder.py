"""Reserve replaceable drag slots using the original carried GIFs, losslessly.

No subject resizing or palette quantization. Right clips copy original bytes;
left clips mirror their decoded pixels with exact per-frame palettes.
"""
from pathlib import Path
from PIL import Image
import json

ROOT = Path(__file__).resolve().parents[1]
SLOTS = [('drag-enter', 'cat-carried.gif', False),
         ('drag', 'cat-carried-hold.gif', True),
         ('drag-exit', 'cat-carried-return.gif', False)]


def mirrored_palette(frame):
    rgba = frame.convert('RGBA').transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    colors = list(dict.fromkeys(pixel[:3] for pixel in rgba.getdata() if pixel[3]))
    assert len(colors) <= 255, 'Original GIF must reserve a transparent index'
    lookup = {rgb: i for i, rgb in enumerate(colors)}
    out = Image.new('P', rgba.size)
    out.putpalette([channel for rgb in colors for channel in rgb] + [0] * (768-len(colors)*3))
    out.putdata([lookup[pixel[:3]] if pixel[3] else 255 for pixel in rgba.getdata()])
    out.info['transparency'] = 255
    return out


def install(catalog, directory):
    for name, filename, loop in SLOTS:
        source = ROOT/'apps/macos/Assets'/filename
        original = Image.open(source)
        frames, durations = [], []
        for index in range(original.n_frames):
            original.seek(index)
            frames.append(mirrored_palette(original))
            durations.append(original.info['duration'])
        for direction in ['right', 'left']:
            full = name+'-'+direction
            dest = directory/(full+'.gif')
            if direction == 'right':
                data = source.read_bytes()
                if not loop:
                    data = data.replace(b'\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00', b'')
                dest.write_bytes(data)
            else:
                frames[0].save(dest, save_all=True, append_images=frames[1:],
                               duration=durations, **({'loop': 0} if loop else {}),
                               transparency=255, disposal=2, optimize=False)
            catalog[full] = {
                'file': dest.name, 'duration': sum(durations)/1000,
                'frames': len(frames), 'fps': len(frames)*1000/sum(durations),
                'frameDurations': [ms/1000 for ms in durations],
                'source': filename, 'placeholder': True, 'loop': loop, 'stride': 0,
                'width': original.width, 'height': original.height,
                'footX': original.width/2, 'footY': 146, 'scale': 1.0,
                'mirrored': direction == 'left',
            }


if __name__ == '__main__':
    directory = ROOT/'apps/macos/Assets/Behavior'
    catalog = json.loads((directory/'catalog.json').read_text())
    install(catalog, directory)
    (directory/'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n')
    print('Installed six drag slots from original carried GIFs without resampling')
