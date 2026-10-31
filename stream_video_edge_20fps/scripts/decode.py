from pathlib import Path
import sys,json,zlib,numpy as np
from PIL import Image,ImageDraw
r=Path(__file__).resolve().parents[1];sys.path.insert(0,str(r));label=sys.argv[1];b=r/'reports'
m=json.loads((b/f'{label}.json').read_text());w,h=m['width'],m['height'];lines=(b/f'{label}.blocks.txt').read_text().splitlines()
assert len(lines)==m['blocks']
data=b''
for i,line in enumerate(lines):
 n,v=line.split();assert int(n)==i and len(v)==m.get('block_words',128)*4;data+=int(v,16).to_bytes(m.get('block_words',128)*2,'little')
data=data[:w*h*2];a=np.frombuffer(data,np.uint8).reshape(h,w,2)
(b/f'{label}.bin').write_bytes(data)
for i,name in [(0,'display'),(1,'raw')]:Image.fromarray(a[:,:,i]).save(b/f'{label}_{name}.png')
c=Image.new('RGB',(w*2,h+25),'white');d=ImageDraw.Draw(c);d.text((5,5),'LCD output diagnostic sample',fill='black');d.text((w+5,5),m.get('plane1','Same-frame raw Y'),fill='black')
c.paste(Image.fromarray(a[:,:,0]).convert('RGB'),(0,25));c.paste(Image.fromarray(a[:,:,1]).convert('RGB'),(w,25));c.save(b/f'{label}_comparison.png')
if m.get('roi') and m['full_width']==630:
 from model.reference import process
 _,local_edge=process(a[:,:,1],threshold=128)
 roi_actual=a[5:-5,5:-5,0]
 mismatch=int(np.count_nonzero(roi_actual!=local_edge))
 (b/f'{label}_core_check.json').write_text(json.dumps(dict(compared_pixels=int(local_edge.size),mismatches=mismatch)))
 assert mismatch==0,f"same-frame native ROI core mismatch: {mismatch}"
if m['internal']:
 from model.reference import pattern,process
 image=pattern(640,480,7);f=1 if 'gaussian' in label else 0
 if m['full_width']==630:raw,expected=process(image,threshold=128)
 else:expected=image;raw=image
 if m.get('roi'):
  x=m['roi_x']-(5 if m['full_width']==630 else 0);y=m['roi_y']-(5 if m['full_width']==630 else 0)
  assert np.array_equal(a[:,:,0],expected[y:y+h,x:x+w])
  assert np.array_equal(a[:,:,1],raw[y:y+h,x:x+w])
 else:
  assert np.array_equal(a[:,:,0],expected[m.get('sample_y',0)::m.get('stride',2),m.get('sample_x',1)::m.get('stride',2)])
  assert np.array_equal(a[:,:,1],raw[m.get('sample_y',0)::m.get('stride',2),m.get('sample_x',1)::m.get('stride',2)])
print(json.dumps(dict(label=label,frame=m['frame'],width=w,height=h,display_crc32=f'{zlib.crc32(a[:,:,0].tobytes()):08x}',comparison=str(b/f'{label}_comparison.png'))))
