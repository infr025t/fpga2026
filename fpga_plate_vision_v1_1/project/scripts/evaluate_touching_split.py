"""固定模型、同图对照；真值只在所有预测完成后用于评分。"""
from pathlib import Path
from collections import Counter
import json,sys
import cv2
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'pc'))
from segment_ref import segment_frame
from norm_ref import normalize_frame,SCENES
from integer_cnn import load,logits
from plate_locator import locate_plate

model=load(ROOT/'model');rows=[]
def evaluate(name,raw,roi,flags,prefix,truth,source):
    old=segment_frame(raw,roi,flags,skip_prefix=prefix)
    new=segment_frame(raw,roi,flags,skip_prefix=prefix,split_touching=True)
    texts=[]
    for seg in [old,new]:
        patches=[normalize_frame(raw,b,roi,flags)[0] for b in seg['boxes']]
        texts.append(''.join('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'[i] for i in logits(np.stack(patches),model).argmax(1)) if patches else '')
    rows.append(dict(scene=name,source=str(source),roi=roi,flags=flags,prefix=prefix,old_boxes=old['boxes'],new_boxes=new['boxes'],old=texts[0],new=texts[1],truth_for_scoring_only=truth,status=new['status']))

for name in ['current_roi_auto_100','current_roi_precheck','osd_board_20','placement_test_03','prefix_board_20']:
    for p in sorted((ROOT.parent/'evidence/baseline/reports'/name/'frames').glob('*/result.json')):
        r=json.loads(p.read_text());raw=np.load(p.parent/'raw.npy');roi=locate_plate(raw)
        if roi is None:raise ValueError(f'No plate in {p}')
        evaluate(name,raw,roi,0,True,'BD12345',p.parent/'raw.npy')
for name,folder,roi,rotation,invert,truth in SCENES:
    for p in sorted(Path(folder).glob('*_selected.png')):
        evaluate(name,cv2.imread(str(p),0),roi,int(bool(rotation))+2*int(invert),False,truth,p)
summaries=[]
for name in dict.fromkeys(r['scene'] for r in rows):
    rs=[r for r in rows if r['scene']==name]
    summaries.append(dict(scene=name,frames=len(rs),old_exact=sum(r['old']==r['truth_for_scoring_only'] for r in rs),new_exact=sum(r['new']==r['truth_for_scoring_only'] for r in rs),new_regressions=sum(r['old']==r['truth_for_scoring_only'] and r['new']!=r['truth_for_scoring_only'] for r in rs),boxes_changed=sum(r['old_boxes']!=r['new_boxes'] for r in rs),old_predictions=dict(Counter(r['old'] for r in rs)),new_predictions=dict(Counter(r['new'] for r in rs))))
out=ROOT/'reports/split_reference';out.mkdir(exist_ok=True)
(out/'frames.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
summary=dict(frames=len(rows),scenes=summaries,regressions=sum(r['new_regressions'] for r in summaries),scope='Stored scenes; no model changes; no class/answer-directed splitting; not independent generalization evidence')
(out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary,indent=2))
assert summary['regressions']==0
