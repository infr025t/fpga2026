"""生成字符数据；禁止读取相机目录或车牌真值。"""
from pathlib import Path
import sys,json,hashlib
import cv2,numpy as np
from PIL import Image,ImageDraw,ImageFont
from frontend import feature_patch,CLASSES
ROOT=Path(__file__).resolve().parent
FONTS={
 'train':['arial.ttf','arialbd.ttf','ariali.ttf','arialbi.ttf','ARIALN.TTF','ARIALNB.TTF','ARIALNI.TTF','ARIALNBI.TTF','calibri.ttf','calibrib.ttf','calibrii.ttf','calibriz.ttf','consola.ttf','consolab.ttf','consolai.ttf','consolaz.ttf','bahnschrift.ttf','tahoma.ttf','tahomabd.ttf','trebuc.ttf','trebucbd.ttf','trebucit.ttf','trebucbi.ttf','impact.ttf'],
 'validation':['segoeui.ttf','segoeuib.ttf','segoeuii.ttf','verdana.ttf','verdanab.ttf','verdanai.ttf'],
 'test':['cour.ttf','courbd.ttf','courbi.ttf','couri.ttf','times.ttf','timesbd.ttf','timesbi.ttf','timesi.ttf']}

def render(ch,font,rng):
 bg=int(rng.integers(140,246));fg=int(rng.integers(5,min(bg-40,110)))
 im=Image.new('L',(130,130),bg);d=ImageDraw.Draw(im);f=ImageFont.truetype(str(Path('C:/Windows/Fonts')/font),72)
 bb=d.textbbox((0,0),ch,font=f);d.text((15-bb[0],15-bb[1]),ch,font=f,fill=fg,stroke_width=int(rng.choice([0,0,0,1])))
 a=np.array(im);ys,xs=np.where(a<(bg+fg)/2);a=a[ys.min()-5:ys.max()+6,xs.min()-5:xs.max()+6]
 h=int(rng.integers(13,47));w=max(5,round(a.shape[1]/a.shape[0]*h*rng.uniform(.6,1.25)))
 a=cv2.resize(a,(w,h),interpolation=cv2.INTER_AREA);a=np.pad(a,((8,8),(8,8)),constant_values=bg)
 angle=float(rng.uniform(-9,9));m=cv2.getRotationMatrix2D((a.shape[1]/2,a.shape[0]/2),angle,1)
 m[0,1]+=float(rng.uniform(-.12,.12));a=cv2.warpAffine(a,m,(a.shape[1],a.shape[0]),borderValue=bg)
 a=cv2.GaussianBlur(a,(3,3),float(rng.uniform(.1,.8)))
 slope=rng.uniform(-10,10)*np.linspace(-1,1,a.shape[1])[None,:]
 a=np.clip(a.astype(float)+slope+rng.normal(0,rng.uniform(.3,3),a.shape),0,255).astype(np.uint8)
 # 极细字经缩小模糊后可能达不到原墨色阈值；用成像后的对比度定位，不生成空标签。
 if bg-int(a.min())<20:return render(ch,font,rng)
 ys,xs=np.where(a<(bg+int(a.min()))/2);box=(int(xs.min()),int(ys.min()),int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1))
 return a,box

def main():
 dest=ROOT/'data';dest.mkdir(exist_ok=True);manifest={}
 for split,repeat,seed in [('train',24,77331),('validation',10,99231),('test',10,48331)]:
  rng=np.random.default_rng(seed);gray=[];edge=[];labels=[]
  for font in FONTS[split]:
   for label,ch in enumerate(CLASSES):
    for _ in range(repeat):
     a,b=render(ch,font,rng)
     dx=int(rng.integers(-1,2));dy=int(rng.integers(-1,2));mat=np.array([[1,0,dx],[0,1,dy]],np.float32)
     for kind,out in [('gray',gray),('edge_norm',edge)]:
      p=feature_patch(a,b,(24,32),kind);p=cv2.warpAffine(p,mat,(24,32),flags=cv2.INTER_NEAREST,borderValue=0);out.append(p)
     labels.append(label)
   print('FONT',split,font,flush=True)
  p=dest/f'{split}.npz';np.savez_compressed(p,gray=np.array(gray,np.uint8),edge_norm=np.array(edge,np.uint8),labels=np.array(labels,np.int64))
  manifest[split]=dict(fonts=FONTS[split],seed=seed,samples=len(labels),sha256=hashlib.sha256(p.read_bytes()).hexdigest())
 (dest/'manifest.json').write_text(json.dumps(manifest,indent=2));print('DATA_READY',flush=True)
if __name__=='__main__':main()
