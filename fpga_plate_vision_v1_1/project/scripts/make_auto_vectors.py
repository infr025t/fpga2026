"""自主链路黄金向量：原图只作为源输入，框和字符不反馈给RTL。"""
from pathlib import Path
import sys,json,hashlib
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'pc'))
from segment_ref import segment_frame
from norm_ref import normalize_frame
from integer_cnn import load,logits
src=ROOT.parent/'evidence/baseline/reports/segmentation_reference/vectors/ddn7870.frame.mem'
raw=np.array([int(v,16) for v in src.read_text().split()],np.uint8).reshape(120,160)
roi=(26,35,158,87);seg=segment_frame(raw,roi)
assert seg['status']==0 and len(seg['boxes'])==7
patches=np.array([normalize_frame(raw,b,roi,0)[0] for b in seg['boxes']])
scores=logits(patches,load(ROOT/'model'))
classes=np.argmax(scores,axis=1)
ascii_codes=[ord('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'[i]) for i in classes]
out=ROOT/'sim/auto_vectors';out.mkdir(exist_ok=True)
for name,values,width in [('frame',raw.ravel(),2),('pixels',patches.ravel(),2),('scores',scores.ravel(),8),('ascii',ascii_codes,2),('boxes',[int.from_bytes(bytes(b),'little') for b in seg['boxes']],8)]:
    (out/f'{name}.hex').write_text(''.join(f'{int(v)&((1<<(4*width))-1):0{width}x}\n' for v in values))
(out/'manifest.json').write_text(json.dumps(dict(source=str(src),sha256=hashlib.sha256(raw.tobytes()).hexdigest(),roi=roi,boxes=seg['boxes'],prediction=''.join(map(chr,ascii_codes))),indent=2))
print('Generated autonomous source and all seven-character comparison vectors')
