from pathlib import Path
import sys,json,numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'pc'))
from plate_locator import locate_plate
root=Path(__file__).resolve().parents[1];out=root/'sim/locator_vectors';out.mkdir(exist_ok=True)
cases=[]
for dx in [-8,0,6]:
 for dy in [-24,0,28]:
  a=np.full((120,160),40,np.uint8);x,y=12+dx,35+dy;a[y:y+36,x:x+140]=230
  for cx in range(x+10,x+125,18):a[y+8:y+30,cx:cx+6]=20
  cases.append((f'shift_{dx+8}_{dy+24}',a))
for value in [0,90,255]:cases.append((f'blank{value}',np.full((120,160),value,np.uint8)))
for gap in [2,3]:
 a=np.full((120,160),20,np.uint8);a[30:66,10:150]=240;a[30:66,60:60+gap]=0
 cases.append((f'header_gap{gap}',a))
a=np.full((120,160),20,np.uint8);a[5:20,20:90]=240;a[60:96,10:150]=240
cases.append(('choose_larger_band',a))
for x,w in [(0,140),(20,140)]:
 a=np.full((120,160),20,np.uint8);a[30:66,x:x+w]=240;cases.append((f'horizontal_clip{x}',a))
for name,y,h in [('top_clip',0,36),('bottom_clip',90,30),('too_tall',10,80)]:
 a=np.full((120,160),40,np.uint8);a[y:y+h,10:150]=230;cases.append((name,a))
for folder in ['current_roi_auto_100','current_roi_precheck','osd_board_20']:
 ps=sorted((root/'reports'/folder/'frames').glob('*/raw.npy'))
 for i,p in enumerate([ps[0],ps[-1]]):cases.append((f'{folder}_{i}',np.load(p)))
lines=[];manifest=[]
for name,a in cases:
 roi=locate_plate(a);(out/f'{name}.mem').write_text(''.join(f'{v:02x}\n' for v in a.ravel()))
 lines.append(' '.join(map(str,[name,int(roi is not None),*(roi or (0,0,0,0))])))
 manifest.append(dict(name=name,roi=roi))
(out/'manifest.txt').write_text('\n'.join(lines)+'\n');(out/'count.txt').write_text(str(len(cases)))
(out/'manifest.json').write_text(json.dumps(manifest,indent=2));print(len(cases),'locator vectors')
