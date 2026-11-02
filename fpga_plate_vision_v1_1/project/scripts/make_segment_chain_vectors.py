"""Golden-only references for the real NSG1 -> FPGA-box -> NCH1 UART chain."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'pc'))
from norm_ref import normalize_frame,MODEL_SHA
from segment_ref import segment_frame
from integer_cnn import load,logits
from norm_protocol import pack_frame,pack_segment
source=ROOT.parent/'evidence/baseline/reports/segmentation_reference/vectors'
out=ROOT/'sim/segment_chain_vectors';out.mkdir(exist_ok=True)
manifest=json.loads((source/'manifest.json').read_text())
assert hashlib.sha256((ROOT/'model/model.bin').read_bytes()).hexdigest()==MODEL_SHA
model=load(ROOT/'model');frames=[];segments=[];pixels=[];scores=[];boxes=[];counts=[];records=[]
for i,name in enumerate(('anp639','d12345')):
    row=next(r for r in manifest if r['name']==name)
    frame=np.array([int(x,16) for x in (source/f'{name}.frame.mem').read_text().split()],np.uint8).reshape(120,160)
    assert hashlib.sha256(frame.tobytes()).hexdigest()==row['input_sha256']
    result=segment_frame(frame,row['roi'],row['flags'])
    assert result['status']==0 and result['boxes'] and [list(b) for b in result['boxes']]==row['boxes']
    patch,_=normalize_frame(frame,result['boxes'][0],row['roi'],row['flags'])
    score=logits(patch,model)[0]
    frames.extend(pack_frame(100+i,frame));segments.extend(pack_segment(200+i,100+i,row['roi'],row['flags']))
    pixels.extend(patch.ravel());scores.extend(score);counts.append(len(result['boxes']))
    boxes.extend(int.from_bytes(bytes(b),'little') for b in result['boxes'])
    boxes.extend([0]*(64-len(result['boxes'])))
    records.append(dict(name=name,frame_id=100+i,segment_sequence=200+i,character_sequence=300+i,roi=row['roi'],flags=row['flags'],golden_boxes=result['boxes'],frame_sha256=hashlib.sha256(frame.tobytes()).hexdigest(),pixels_sha256=hashlib.sha256(patch.tobytes()).hexdigest(),scores=[int(s) for s in score],character_descriptor_source='Built by HDL testbench from received FPGA NSR1 first box, never fed from golden boxes'))
for name,values,width in [('frames',frames,2),('segments',segments,2),('pixels',pixels,2),('scores',scores,8),('boxes',boxes,8),('counts',counts,2)]:
    (out/f'{name}.hex').write_text(''.join(f'{int(v)&((1<<(4*width))-1):0{width}x}\n' for v in values),encoding='ascii')
(out/'manifest.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
print('Generated 2 real-frame NSG chains; golden boxes only for comparison; 1536 pixels and 72 signed scores')
