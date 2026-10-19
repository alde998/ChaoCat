#!/usr/bin/env python3
"""Review every frame at its actual display scale, with shared floor/origin."""
import json
import hashlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "apps/macos/Assets/Behavior"
OUT = ROOT / "exports/animation-audit"


def pose(clip, index):
    with Image.open(ASSETS / clip["file"]) as image:
        image.seek(index if index >= 0 else image.n_frames + index)
        return image.convert("RGBA")


def paint(canvas, clip, frame, origin, zoom=2):
    factor = clip["scale"] * zoom
    shown = frame.resize((round(frame.width * factor), round(frame.height * factor)), Image.Resampling.LANCZOS)
    canvas.paste(shown, (round(origin[0]-clip["footX"]*factor), round(origin[1]-clip["footY"]*factor)), shown)


def main():
    OUT.mkdir(exist_ok=True)
    catalog = json.loads((ASSETS / "catalog.json").read_text())
    names = [n for n in catalog if n.endswith("-right") and not n.startswith("bug-")]
    report = []
    for name, clip in catalog.items():
        image = Image.open(ASSETS / clip["file"])
        durations, bounds, opaque_edges = [], [], []
        for i in range(image.n_frames):
            image.seek(i)
            alpha = image.convert("RGBA").getchannel("A")
            box = alpha.getbbox()
            assert box is not None, (name, i, "blank")
            bounds.append([round((box[0]-clip["footX"])*clip["scale"], 2),
                           round((box[1]-clip["footY"])*clip["scale"], 2),
                           round((box[2]-clip["footX"])*clip["scale"], 2),
                           round((box[3]-clip["footY"])*clip["scale"], 2)])
            if box[0]==0 or box[1]==0 or box[2]==image.width or box[3]==image.height:
                opaque_edges.append(i)
            durations.append(image.info["duration"])
        assert len(durations)==clip["frames"] and abs(sum(durations)/1000-clip["duration"])<0.001
        report.append(dict(clip=name, frames=len(durations), scale=clip["scale"],
                           foot=[clip["footX"],clip["footY"]], frameBounds=bounds,
                           canvasEdgeFrames=opaque_edges,
                           sha256=hashlib.sha256((ASSETS/clip["file"]).read_bytes()).hexdigest()))
    for page in range((len(names)+5)//6):
        sheet=Image.new("RGB",(1260,1860),"#f3f4f6");draw=ImageDraw.Draw(sheet)
        for row,name in enumerate(names[page*6:page*6+6]):
            c=catalog[name]
            for col,i in enumerate([0,c["frames"]//2,c["frames"]-1]):
                origin=(col*420+210,row*310+280)
                draw.line((col*420,origin[1],(col+1)*420,origin[1]),fill="#b6bec9")
                draw.line((origin[0],row*310+25,origin[0],origin[1]+8),fill="#e1e4e8")
                paint(sheet,c,pose(c,i),origin)
                draw.text((col*420+6,row*310+5),f"{name}  frame {i}",fill="#101820")
        sheet.save(OUT/f"after-{page+1}.jpg")

    before=json.loads((OUT/"catalog-before.json").read_text())
    phases=["walk","chase-run","catch","chase","rubbish-run","rubbish-jump"]
    sheet=Image.new("RGB",(900,6*280),"#f3f4f6");draw=ImageDraw.Draw(sheet)
    for row,phase in enumerate(phases):
        name=phase+"-right"
        for col,cat in enumerate([before,catalog]):
            origin=(col*450+225,row*280+255)
            draw.line((col*450,origin[1],(col+1)*450,origin[1]),fill="#b6bec9")
            draw.line((origin[0],row*280+25,origin[0],origin[1]+8),fill="#e1e4e8")
            paint(sheet,cat[name],pose(cat[name],0),origin)
            draw.text((col*450+6,row*280+5),f"{'BEFORE' if col==0 else 'AFTER'} {phase}",fill="#101820")
    sheet.save(OUT/"calibration-comparison.jpg")
    # Review the actual sequences, with fixed registration. GIFs are preview
    # exports only; no asset is re-encoded or spatially resampled in the app.
    for direction in ("left","right"):
        sequence=["walk","chase-run","chase-run","catch","chase","catch","chase-roll","chase-recover","chase","catch","chase-exit","walk"]
        frames,delays=[],[]
        for phase in sequence:
            c=catalog[phase+"-"+direction];im=Image.open(ASSETS/c["file"])
            for i in range(im.n_frames):
                im.seek(i);frame=Image.new("RGB",(480,320),"#f3f4f6")
                draw=ImageDraw.Draw(frame);draw.line((0,290,480,290),fill="#b6bec9")
                draw.text((12,12),phase+" / "+direction,fill="#101820")
                paint(frame,c,im.convert("RGBA"),(240,290))
                frames.append(frame.quantize(colors=256));delays.append(im.info["duration"])
        frames[0].save(OUT/f"chase-transitions-{direction}.gif",save_all=True,append_images=frames[1:],duration=delays,loop=0,disposal=2)
    (OUT/"frame-audit.json").write_text(json.dumps(report,indent=2)+"\n")
    print(f"Audited {len(report)} entries / {sum(r['frames'] for r in report)} frames; 6 full contact sheets, before/after and both chase sequences")
    print("Canvas edge frames:",[(r['clip'],r['canvasEdgeFrames']) for r in report if r['canvasEdgeFrames']])


if __name__=="__main__":main()
