from pathlib import Path
from PIL import Image,ImageChops,ImageStat
import json
root=Path(__file__).resolve().parents[1]
folder=root/'apps/macos/Assets/Behavior';catalog=json.loads((folder/'catalog.json').read_text());report=[]
assert len(catalog)==70
for name,c in catalog.items():
 expected_scale=0.21503 if c.get('source') in ('M02.mp4','M03.mp4') else 0.12 if c.get('source')=='drag-click-lift-drop.mp4' else 0.11 if name.startswith('bug-') else 0.2094 if c.get('source')=='追虫.mp4' else 0.19036
 if name.startswith(('chase-run-','rubbish-run-')):expected_scale=0.180842
 if name.startswith('rubbish-jump-'):expected_scale=0.228432
 if name.startswith('chase-run-'):
  original=catalog[c['displayVariantOf']]
  assert c['file']==original['file'] and c['frames']==original['frames'],(name,'preserve original sprint pixels')
 assert abs(c['scale']-expected_scale)<0.00001,(name,'inconsistent display scale')
 im=Image.open(folder/c['file']);assert im.n_frames==c['frames'],(name,im.n_frames,c['frames'])
 assert im.size==(c['width'],c['height'])
 assert (im.info.get('loop')==0)==c['loop'],(name,'GIF repeat flag')
 duration=0
 for i in range(im.n_frames):
  im.seek(i);duration+=im.info['duration'];a=im.convert('RGBA').getchannel('A')
  assert a.getbbox() is not None,(name,i,'empty');assert a.getextrema()==(0,255),(name,i,'opaque')
 assert abs(duration/1000-c['duration'])<0.001,(name,duration)
 if c.get('placeholder'):
  original=Image.open(folder.parent/c['source'])
  assert original.n_frames==im.n_frames
  for i in range(im.n_frames):
   original.seek(i);im.seek(i)
   assert original.info['duration']==im.info['duration']
   expected=original.convert('RGBA')
   if c['mirrored']:expected=expected.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
   # Transparent RGB is not visible; compare the composite and alpha exactly.
   actual=im.convert('RGBA')
   assert expected.getchannel('A').tobytes()==actual.getchannel('A').tobytes(),(name,i,'legacy alpha')
   bg=Image.new('RGBA',im.size,'#d0d0d0')
   assert Image.alpha_composite(bg,expected).tobytes()==Image.alpha_composite(bg,actual).tobytes(),(name,i,'legacy pixels')
 if c.get('source')=='drag-click-lift-drop.mp4':
  assert not c.get('placeholder') and c['fps']==24 and im.size==(834,1112),(name,'source quality')
  im.seek(0);assert im.convert('RGBA').getpixel((0,0))[3]==0,(name,'blue screen remains')
 if name=='rubbish-tail-right':
  im.seek(0)
  assert im.convert('RGBA').getchannel('A').getbbox()[1]<=324,(name,'tail tip clipped')
  for i in range(im.n_frames):
   im.seek(i)
   base=im.convert('RGBA').crop((760,515,806,548))
   assert not any(r>230 and g>145 and b<115 and a>0 for r,g,b,a in base.get_flattened_data()),(name,i,'wrapper pixels')
 if name in ('chase-enter-right','catch-right'):
  frame,box=(40,(714,574,800,600)) if name=='chase-enter-right' else (0,(789,626,863,657))
  im.seek(frame)
  collar=im.convert('RGBA').crop(box)
  teal=sum(a>0 and g>r+8 and g>b+20 and b<r for r,g,b,a in collar.get_flattened_data())
  assert teal>350,(name,'collar color was removed')
 if name=='catch-right':
  im.seek(im.n_frames-1)
  trail=im.convert('RGBA').crop((1100,300,1350,650))
  assert not any(a>0 and r>=100 and g>r+8 and b>r+8 and abs(g-b)<=30
                 for r,g,b,a in trail.get_flattened_data()),(name,'cyan flight trail remains')
 if name.startswith('catch-'):
  original=Image.open(root/'media/chase-roll-sources'/f'{name}-before-trim.gif')
  for i,source_index in enumerate(c['retainedFrames']):
   im.seek(i);original.seek(source_index)
   actual=im.convert('RGBA');expected=original.convert('RGBA')
   assert actual.getchannel('A').tobytes()==expected.getchannel('A').tobytes()
   bg=Image.new('RGBA',im.size,'#ddd')
   assert Image.alpha_composite(bg,actual).tobytes()==Image.alpha_composite(bg,expected).tobytes(),(name,i,'retained pixels changed')
   assert actual.getchannel('A').getbbox()[1]>300,(name,i,'clipped ears remain')
 if c['loop']:
  im.seek(0);first=im.convert('RGBA');im.seek(im.n_frames-1);last=im.convert('RGBA')
  if c.get('source')=='drag-click-lift-drop.mp4':
   backdrop=Image.new('RGBA',im.size,'#e8ebed')
   difference=ImageChops.difference(Image.alpha_composite(backdrop,first),Image.alpha_composite(backdrop,last))
   assert max(ImageStat.Stat(difference).mean[:3])<15,(name,'loop seam')
  else:assert ImageChops.difference(first,last).getbbox() is None,(name,'loop seam')
 if name.endswith('-right'):
  left=Image.open(folder/catalog[name[:-6]+'-left']['file']);im.seek(im.n_frames//2);left.seek(left.n_frames//2)
  mirror=ImageChops.difference(im.convert('RGBA').getchannel('A').transpose(Image.Transpose.FLIP_LEFT_RIGHT),left.convert('RGBA').getchannel('A'))
  if c.get('source')=='drag-click-lift-drop.mp4':
   assert max(ImageStat.Stat(mirror).mean)<1,(name,'mirror')
  else:assert mirror.getbbox() is None,(name,'mirror')
 report.append({'clip':name,'frames':im.n_frames,'seconds':duration/1000,'transparent':True})
for direction in ('left','right'):
 sizes=[]
 for name,index in ((f'drag-exit-{direction}',-1),(f'sit-up-{direction}',0)):
  clip=catalog[name];im=Image.open(folder/clip['file']);im.seek(index if index>=0 else im.n_frames+index)
  left,top,right,bottom=im.convert('RGBA').getchannel('A').getbbox()
  sizes.append(((right-left)*clip['scale'],(bottom-top)*clip['scale']))
 assert all(abs(first-second)<0.5 for first,second in zip(*sizes)),(direction,'landing-to-stand scale mismatch',sizes)
 walk=catalog[f'walk-{direction}'];im=Image.open(folder/walk['file']);im.seek(0)
 top,bottom=im.convert('RGBA').getchannel('A').getbbox()[1::2]
 walk_height=(bottom-top)*walk['scale']
 for name,index in ((f'chase-enter-{direction}',0),(f'chase-exit-{direction}',-1)):
  clip=catalog[name];im=Image.open(folder/clip['file']);im.seek(index if index>=0 else im.n_frames+index)
  top,bottom=im.convert('RGBA').getchannel('A').getbbox()[1::2]
  assert abs((bottom-top)*clip['scale']-walk_height)<2,(name,'neutral cat height differs from walk')
 jump=catalog[f'rubbish-jump-{direction}'];assert jump['start']==152 and jump['frames']==8
 # Compare anatomical head widths, not airborne height or stretched tails.
 # Native landmark spans measured in the contact-sheet audit (frame 0).
 head_widths=[catalog[f'{name}-{direction}']['scale']*width for name,width in
              [('walk',210),('rubbish-run',225),('rubbish-jump',180),('catch',198),('chase',190)]]
 assert max(head_widths)-min(head_widths)<2,(direction,'head size mismatch',head_widths)
 for phase in ('chase-enter','catch','chase-exit'):
  clip=catalog[f'{phase}-{direction}'];im=Image.open(folder/clip['file']);im.seek(0)
  # Their ground shadow/contact was 30–40 screen points left of the origin.
  pixels=im.convert('RGBA');dark=[]
  for y in range(860,915):
   row=[x for x in range(im.width) if pixels.getpixel((x,y))[3]>0 and max(pixels.getpixel((x,y))[:3])<90]
   if row:dark.append((len(row),(min(row)+max(row))/2))
  center=max(dark)[1]
  assert abs((center-clip['footX'])*clip['scale'])<10,(phase,direction,'ground anchor jumps')
(root/'docs/behavior-assets-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'{len(catalog)} GIFs: display scale, landing seam, frames, timing, transparency, mirrors and loop seams')
