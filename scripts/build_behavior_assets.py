#!/usr/bin/env python3
"""Build the user-named 2026-10-14 behaviors without resampling subject pixels.
Requires Pillow, numpy, scipy. Input: native PNG folders named like the videos.
"""
import argparse,json,hashlib
from pathlib import Path
import numpy as np
from scipy import ndimage as ndi
from PIL import Image, ImageDraw
from repair_rubbish_matte import rubbish_matte
from install_drag_placeholder import install as install_drag_placeholder
from clean_rubbish_tail import clean_frame as clean_rubbish_tail_frame
from refine_behavior_gifs import encode_chase_frame, remove_chase_bleed

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'apps/macos/Assets/Behavior'
CAT_SCALE=0.19036
CHASE_SCALE=round(CAT_SCALE*1.1,5)
# Half-open source ranges. Cyclic phases receive a short seam blend, not a speed change.
SPECS=[
 ('walk','走路',0,24,True,68),
 ('turn-out','向外转身过渡',12,42,False,0),
 ('turn-in','向内转身过渡',12,56,False,0),
 ('run','受惊狂奔',24,56,True,180),
 ('run-enter','受惊狂奔',0,24,False,0),
 ('run-exit','受惊狂奔',0,24,False,0),
 ('run-turn-in','向内狂奔过渡',12,53,False,0),
 ('run-turn-out','向外狂奔过渡',10,56,False,0),
 ('sit-down','蹲坐舔爪',24,84,False,0),
 ('sit','蹲坐舔爪',84,126,False,0),
 ('lick','蹲坐舔爪',126,187,True,0),
 ('sit-up','蹲坐舔爪',284,337,False,0),
 ('sleep-down','入睡起身',30,115,False,0),
 ('sleep','入睡起身',135,183,True,0),
 ('sleep-up','入睡起身',248,337,False,0),
 ('poop','拉屎',24,145,False,0),
 ('bury-down','埋屎',20,78,False,0),
 ('bury','埋屎',78,151,False,0),
 ('bury-up','埋屎',151,197,False,0),
 ('rubbish-discover','跳垃圾堆',24,102,False,0),
 ('rubbish-run','跳垃圾堆',108,137,True,170),
 ('rubbish-jump','跳垃圾堆',152,160,False,0),
 ('rubbish-tail','跳垃圾堆',240,289,True,0),
 ('chase-enter','追虫',0,61,False,0),
 ('chase','追虫',233,253,True,142),
 ('catch','追虫',65,126,False,0),
 ('chase-exit','追虫',253,289,False,0),
 ('bug-fly','追虫',24,60,True,0),
 ('bug-escape','追虫',80,120,True,0),
]

def key(im, preserve_blue=False):
 a=np.array(im.convert('RGB'));v=a.astype(np.int16);r,g,b=v.transpose(2,0,1)
 candidate=(b>100)&(b-r>35)&(b-g>22)
 # Border-connected blue screen. Preserve blue wrappers enclosed in the trash.
 seeds=np.zeros(candidate.shape,bool);seeds[0]=candidate[0];seeds[-1]=candidate[-1];seeds[:,0]=candidate[:,0];seeds[:,-1]=candidate[:,-1]
 bg=ndi.binary_propagation(seeds,mask=candidate)
 # Tiny enclosed blue gaps between legs are background; large enclosed areas
 # (blue wrappers) retain their color. Opening removes compressed edge noise.
 labels,n=ndi.label(candidate & ~bg);sizes=np.bincount(labels.ravel());small=sizes<1600;small[0]=False;bg |= small[labels]
 if not preserve_blue: bg = candidate
 alpha=(~bg).astype(np.uint8)*255
 edge=(~bg)&ndi.binary_dilation(bg,iterations=2)
 a[:,:,2]=np.where(edge,np.minimum(a[:,:,2],np.maximum(a[:,:,0],a[:,:,1])),a[:,:,2])
 return Image.fromarray(np.dstack([a,alpha]))

def separate_bug(im,kind):
 a=np.array(im);alpha=a[:,:,3]>0
 # Label at half size only to classify objects; output alpha uses native pixels.
 lab,n=ndi.label(alpha[::2,::2]);sizes=np.bincount(lab.ravel());sizes[0]=0
 cat=int(sizes.argmax());bug=np.zeros_like(lab,bool)
 for l,sl in enumerate(ndi.find_objects(lab),1):
  if sl is None or l==cat or sizes[l]<20:continue
  yy,xx=sl
  if yy.start*2<360 and sizes[l]<sizes[cat]*0.45:bug |= lab==l
 mask=np.repeat(np.repeat(bug,2,0),2,1)[:alpha.shape[0],:alpha.shape[1]]
 mask=ndi.binary_dilation(mask,iterations=4)
 if kind=='bug':a[:,:,3]=np.where(mask,a[:,:,3],0)
 else:a[:,:,3]=np.where(mask,0,a[:,:,3])
 return Image.fromarray(a)

def tail_mask(im):
 a=np.array(im);r,g,b=a[:,:,:3].astype(np.int16).transpose(2,0,1)
 yy,xx=np.indices(r.shape)
 fur=(r>g*1.15)&(g>b*1.15)&(r<230)&(xx>450)&(xx<800)&(yy<290)
 lab,n=ndi.label(fur);best=0;best_size=0
 for l,sl in enumerate(ndi.find_objects(lab),1):
  if sl and sl[0].start<150 and (lab==l).sum()>best_size:best=l;best_size=(lab==l).sum()
 mask=ndi.binary_fill_holes(ndi.binary_dilation(lab==best,iterations=7)) if best else fur
 a[:,:,3]=np.where(mask,a[:,:,3],0)
 return Image.fromarray(a)

def encode(frames,path,fps,loop,preserve_collar=False,blend_seam=True):
 if loop and blend_seam and len(frames)>8:
  # Close the seam at the original cadence. Alpha is thresholded only by GIF.
  for j in range(3):frames[-3+j]=Image.blend(frames[-3+j],frames[0],(j+1)/3)
 encoded=[]
 for im in frames:
  if preserve_collar:encoded.append(encode_chase_frame(im))
  else:
   rgb=Image.new('RGB',im.size);rgb.paste(im,mask=im.getchannel('A'))
   p=rgb.quantize(colors=255,method=Image.Quantize.MEDIANCUT);p.paste(255,im.getchannel('A').point(lambda v:255 if v<128 else 0));encoded.append(p)
 durations=[10*(round((i+1)*100/fps)-round(i*100/fps)) for i in range(len(frames))]
 encoded[0].save(path,save_all=True,append_images=encoded[1:],duration=durations,**({"loop":0} if loop else {}),disposal=2,transparency=255,optimize=False)
 return sum(durations)/1000

def main():
 p=argparse.ArgumentParser();p.add_argument('frames',type=Path);p.add_argument('--masters-only',action='store_true');args=p.parse_args();OUT.mkdir(parents=True,exist_ok=True)
 catalog={};review=[]
 for source in dict.fromkeys(s[1] for s in SPECS):
  specs=[s for s in SPECS if s[1]==source];indices={i for s in specs for i in range(s[2],s[3])}
  cache={i:key(Image.open(args.frames/source/f'bug_{i:05d}.png'), source=='跳垃圾堆' and i>=240) for i in indices}
  for name,_,start,end,loop,stride in specs:
   fps=30 if source=='埋屎' else 24
   frames=[cache[i].copy() for i in range(start,end)]
   if name=='sleep':
    # Breathing is a one-way authored motion. Play it back down and up so
    # repeated sleep cycles meet on adjacent poses instead of jumping at the seam.
    frames=frames+frames[-2::-1]
   if source=='追虫':frames=[separate_bug(im,'bug' if name.startswith('bug') else 'cat') for im in frames]
   if source=='追虫' and not name.startswith('bug'):frames=[remove_chase_bleed(im)[0] for im in frames]
   if name=='run-exit':frames.reverse()
   if name=='rubbish-tail':frames=[tail_mask(im) for im in frames]
   if name=='rubbish-jump':
    # Before contact, cat and heap are disconnected; keep the component at
    # the cat's body and its ground shadow, never bake a moving heap into it.
    for j,im in enumerate(frames):
     a=np.array(im);lab,n=ndi.label(a[:,:,3]>0);keep=np.zeros(lab.shape,bool)
     for l,sl in enumerate(ndi.find_objects(lab),1):
      if sl and sl[1].start<500 and sl[1].stop-sl[1].start>150:keep |= lab==l
     a[:,:,3]=np.where(keep,a[:,:,3],0);frames[j]=Image.fromarray(a)
   boxes=[im.getchannel('A').getbbox() for im in frames]
   if any(b is None for b in boxes):raise ValueError((name,'empty frame'))
   # Fixed native pixel canvas. Subject geometry is never resized.
   isbug=name.startswith('bug');canvas=(400,400) if isbug else (1600,1000)
   baseline=370 if isbug else 900
   if isbug:
    normalized=[]
    for im,b in zip(frames,boxes):
     dest=Image.new('RGBA',canvas);crop=im.crop(b);dest.alpha_composite(crop,((canvas[0]-crop.width)//2,(canvas[1]-crop.height)//2));normalized.append(dest)
   else:
    center=int(np.median([(b[0]+b[2])/2 for b in boxes]))
    # Source baseline stays fixed for jumping/breathing; do not squash height.
    ground=600 if source=='追虫' else 650
    if name=='rubbish-tail':center=640;ground=650
    normalized=[]
    for im in frames:
     dest=Image.new('RGBA',canvas);dest.alpha_composite(im,(canvas[0]//2-center,baseline-ground));normalized.append(dest)
   if name=='rubbish-tail':normalized=[clean_rubbish_tail_frame(im) for im in normalized]
   for direction in ['right','left']:
    # Turn labels identify DESTINATION direction; original turns right→left.
    mirror=direction=='left'
    if isbug:mirror=direction=='right'  # The source insect faces left.
    if 'turn-' in name:mirror=direction=='right'
    fs=[im.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for im in normalized] if mirror else [im.copy() for im in normalized]
    full=name+'-'+direction
    if direction=='right' and (args.masters_only or name in ('poop','bury-down','bury','rubbish-tail')):
     master=ROOT/'media/behavior-masters';master.mkdir(parents=True,exist_ok=True)
     fs[0].save(master/(name+'.png'),save_all=True,append_images=fs[1:],duration=1000/fps,loop=0,disposal=0,blend=0)
    if args.masters_only:
     duration=round(len(fs)/fps,2)
    else:duration=encode(fs,OUT/(full+'.gif'),fps,loop,preserve_collar=source=='追虫' and not isbug,blend_seam=name!='sleep')
    scale=0.11 if isbug else CHASE_SCALE if source=='追虫' else CAT_SCALE
    catalog[full]={'file':full+'.gif','duration':duration,'frames':len(fs),'fps':fps,'source':source+'.mp4','start':start,'end':end,'loop':loop,'stride':stride if isbug else round(stride*scale/0.18,2),'width':canvas[0],'height':canvas[1],'footX':canvas[0]/2,'footY':baseline,'scale':scale,'mirrored':mirror}
    if name=='poop':catalog[full]['markerTime']=(76-start)/fps
    if name=='bury':catalog[full]['markerTime']=(150-start)/fps
   review.append((name,normalized[len(normalized)//2]));print(name,flush=True)
  if source=='拉屎':cache[90].crop((190,445,443,652)).save(OUT/'poop.png')
  if source=='跳垃圾堆':
   full=rubbish_matte(args.frames/source/'bug_00260.png')
   full.save(OUT/'rubbish.png');full.transpose(Image.Transpose.FLIP_LEFT_RIGHT).save(OUT/'rubbish-left.png')
  del cache
 if not args.masters_only:
  previous=json.loads((OUT/'catalog.json').read_text()) if (OUT/'catalog.json').exists() else {}
  drag_names=[f'{name}-{direction}' for name in ('drag-enter','drag','drag-exit') for direction in ('right','left')]
  if all(previous.get(name,{}).get('source')=='drag-click-lift-drop.mp4' and (OUT/previous[name]['file']).exists() for name in drag_names):
   catalog.update({name:previous[name] for name in drag_names})
  else:
   install_drag_placeholder(catalog, OUT)
  (OUT/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
 sheet=Image.new('RGB',(1000,((len(review)+4)//5)*150),'#d5d9df');d=ImageDraw.Draw(sheet)
 for j,(name,im) in enumerate(review):
  im.thumbnail((195,125));x=j%5*200;y=j//5*150;sheet.paste(im,(x,y),im);d.text((x,y+127),name,fill='black')
 sheet.save(ROOT/'docs/behavior-segments-preview.jpg')
 print('built',len(catalog),'clips')
if __name__=='__main__':main()
