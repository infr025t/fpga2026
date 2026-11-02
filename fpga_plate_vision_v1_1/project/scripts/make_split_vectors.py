"""分割单元向量：实际失败图、平移、反相/旋转、宽字、复位后空图。"""
from pathlib import Path
import json,sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'pc'))
from segment_ref import segment_frame
out=ROOT/'sim/split_vectors';out.mkdir(exist_ok=True)
p=sorted((ROOT.parent/'evidence/baseline/reports/prefix_board_20/frames').glob('*/result.json'))[0]
r=json.loads(p.read_text());raw=np.load(p.parent/'raw.npy');roi=r['roi'];cases=[]
for enabled in [0,1]:cases.append((f'real_{enabled}',raw,roi,0,1,enabled))
for dy,dx in [(-40,-5),(-15,0)]:
    a=np.full_like(raw,30);x0,y0,x1,y1=roi;a[y0+dy:y1+dy,x0+dx:x1+dx]=raw[y0:y1,x0:x1]
    cases.append((f'move_{-dy}',a,(x0+dx,y0+dy,x1+dx,y1+dy),0,1,1))
cases.extend([('rotate',raw[::-1,::-1],roi,1,1,1),('invert',255-raw,roi,2,1,1)])
for kind in ['solid','M','W','thin','thick']:
    a=np.full((120,160),230,np.uint8)
    if kind=='solid':a[20:44,20:47]=0
    else:
        a[20:44,20:23]=0;a[20:44,44:47]=0
        if kind in ['M','W']:
            for dx in range(27):
                yy=int(round(min(dx,26-dx)*20/13));yy=yy if kind=='M' else 20-yy
                a[20+yy:23+yy,20+dx]=0
        else:a[43-(0 if kind=='thin' else 4):44,20:47]=0
    cases.append((kind.lower(),a,(10,10,70,60),0,0,1))
cases.append(('blank',np.full((120,160),97,np.uint8),(0,0,160,120),0,1,1))
lines=[];manifest=[]
for name,a,roi,flags,prefix,split in cases:
    seg=segment_frame(a,roi,flags,skip_prefix=prefix,split_touching=split)
    (out/f'{name}.hex').write_text(''.join(f'{v:02x}\n' for v in a.ravel()))
    lines.append(' '.join(map(str,[name,*roi,flags,prefix,split,seg['status'],len(seg['boxes']),*[n for b in seg['boxes'] for n in b]])))
    manifest.append(dict(name=name,roi=roi,flags=flags,prefix=prefix,split=split,expected=seg))
(out/'manifest.txt').write_text('\n'.join(lines)+'\n');(out/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Generated',len(cases),'cases')
