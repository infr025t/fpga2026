from pathlib import Path
import sys,json,numpy as np
from PIL import Image,ImageDraw
r=Path(__file__).resolve().parents[1];label=sys.argv[1];b=r/'reports'
m=json.loads((b/f'{label}.json').read_text());w,h=m['width'],m['height']
a=np.fromfile(b/f'{label}.bin',np.uint8).reshape(h,w,2)
p0=a[:,:,0];p1=a[:,:,1]
rows=[]
for y in range(h):
 u=p0[y,8:-8].astype(float);v=p1[y,8:-8].astype(float)
 rows.append(dict(sample_y=y,native_y=y*4,p0_mean=float(u.mean()),p1_mean=float(v.mean()),p0_std=float(u.std()),p1_std=float(v.std()),p0_dx=float(np.abs(np.diff(u)).mean()),p1_dx=float(np.abs(np.diff(v)).mean())))
(b/f'{label}_row_statistics.json').write_text(json.dumps(rows,indent=2))
factor=4;canvas=Image.new('RGB',(w*factor*2,h*factor+28),'white');d=ImageDraw.Draw(canvas)
d.text((8,8),'Selected even byte: actual RAW output',fill='black');d.text((w*factor+8,8),'Preceding odd byte: diagnosis only',fill='black')
for i in range(2):
 im=Image.fromarray(np.repeat(np.repeat(a[:,:,i],factor,axis=0),factor,axis=1)).convert('RGB')
 canvas.paste(im,(w*factor*i,28))
canvas.save(b/f'{label}_paired_preview.png')
print(json.dumps(dict(label=label,frame=m['frame'],p0_std=float(p0.std()),p1_std=float(p1.std()),rows=str(b/f'{label}_row_statistics.json'),preview=str(b/f'{label}_paired_preview.png'))))
