"""为真实UART整链生成请求及独立NumPy黄金数据。"""
from pathlib import Path
import hashlib,json,sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'pc'))
from norm_ref import normalize_frame
from integer_cnn import load,logits
from norm_protocol import pack_frame,pack_character
source=ROOT.parent/'evidence/baseline/reports/norm_reference/rtl_vectors'
# 原始生成输入在旧基线中已缺失；不得把冻结向量冒充本次重新生成。
if not (source/'manifest.json').is_file():
 raise SystemExit(f'Original normalization inputs unavailable: {source}. No vectors regenerated; run_norm_chain_sim.ps1 can validate and use frozen sim/norm_chain_vectors instead.')
out=ROOT/'sim/norm_chain_vectors';out.mkdir(exist_ok=True)
manifest=json.loads((source/'manifest.json').read_text())
model=load(ROOT/'model');requests=[];characters=[];pixels=[];scores=[];records=[]
for i,name in enumerate(('anp639','d12345')):
 row=next(r for r in manifest if r['name']==name)
 frame=np.array([int(x,16) for x in (source/f'{name}.frame.mem').read_text().split()],np.uint8).reshape(120,160)
 patch,meta=normalize_frame(frame,row['box'],row['roi'],row['flags'])
 golden=np.array([int(x,16) for x in (source/f'{name}.expected.mem').read_text().split()],np.uint8).reshape(32,24)
 assert np.array_equal(patch,golden)
 score=logits(patch,model)[0]
 requests.extend(pack_frame(100+i,frame));characters.extend(pack_character(200+i,100+i,(*row['box'],*row['roi'],row['flags'])))
 pixels.extend(patch.ravel());scores.extend(score)
 records.append(dict(name=name,frame_id=100+i,sequence=200+i,descriptor=[*row['box'],*row['roi'],row['flags']],frame_sha256=hashlib.sha256(frame.tobytes()).hexdigest(),pixels_sha256=hashlib.sha256(patch.tobytes()).hexdigest(),scores=[int(s) for s in score]))
for name,values,width in [('frames',requests,2),('characters',characters,2),('pixels',pixels,2),('scores',scores,8)]:
 (out/f'{name}.hex').write_text(''.join(f'{int(v)&((1<<(4*width))-1):0{width}x}\n' for v in values),encoding='ascii')
(out/'manifest.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
print('Generated 2 real-frame UART cases, 1536 golden pixels, 72 golden scores')
