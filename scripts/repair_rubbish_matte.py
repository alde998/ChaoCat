"""Extract the complete static heap, preserving blue/purple packaging.
Use connected outline + enclosed regions; the tail has its own animated layer.
"""
from pathlib import Path
import numpy as np
from scipy import ndimage as ndi
from PIL import Image, ImageDraw

def rubbish_matte(source):
 rgb=Image.open(source).convert('RGB');a=np.array(rgb);r,g,b=a.astype(np.int16).transpose(2,0,1)
 blue=(b>100)&(b-r>35)&(b-g>22)
 labels,n=ndi.label(~blue);sizes=np.bincount(labels.ravel());sizes[0]=0
 silhouette=ndi.binary_fill_holes(labels==sizes.argmax())
 # Trace the existing top contour of the two bags. This removes the entire
 # tail without cutting a rectangle through either bag or its black outline.
 exclusion=Image.new('1',rgb.size)
 ImageDraw.Draw(exclusion).polygon([(510,0),(710,0),(710,254),(690,288),(666,290),(641,282),(617,269),(593,254),(574,221),(567,198),(510,198)],fill=1)
 silhouette &= ~np.array(exclusion,dtype=bool)
 out=Image.fromarray(np.dstack([a,silhouette.astype('uint8')*255]))
 canvas=Image.new('RGBA',(1600,1000));canvas.alpha_composite(out,(160,250))
 return canvas

if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('frames',type=Path);args=p.parse_args()
 root=Path(__file__).resolve().parents[1];out=root/'apps/macos/Assets/Behavior'
 im=rubbish_matte(args.frames/'跳垃圾堆/bug_00260.png')
 im.save(out/'rubbish.png');im.transpose(Image.Transpose.FLIP_LEFT_RIGHT).save(out/'rubbish-left.png')
 checker=Image.new('RGB',im.size,'#e4e4e4');d=ImageDraw.Draw(checker)
 for y in range(0,1000,32):
  for x in range(0,1600,32):
   if (x//32+y//32)%2:d.rectangle((x,y,x+31,y+31),fill='#c9c9c9')
 checker.paste(im,mask=im.getchannel('A'));checker.crop((300,425,1300,930)).save(root/'docs/rubbish-matte-review.png')
 print('Complete heap matte exported without tail or motion marks')
