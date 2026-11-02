"""离线复核保存的原图、描述符及板上原始输出，无需串口或板卡。"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from norm_ref import normalize_frame,MODEL_SHA
import integer_cnn as q
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('report',type=Path);args=p.parse_args()
    if hashlib.sha256((ROOT/'model/model.bin').read_bytes()).hexdigest()!=MODEL_SHA:raise ValueError('Model changed')
    model=q.load(ROOT/'model');count=pb=sb=0;cache={}
    for line in (args.report/'characters.jsonl').read_text().splitlines():
        row=json.loads(line);index=row['frame_index'];stem=f"{row['sequence']:06d}"
        if index not in cache:cache[index]=np.frombuffer((args.report/'frames_raw'/f'{index:04d}.bin').read_bytes(),np.uint8).reshape(120,160)
        d=row['descriptor'];expected,_=normalize_frame(cache[index],d[:4],d[4:8],d[8])
        actual=np.frombuffer((args.report/'normalized'/f'{stem}.bin').read_bytes(),np.uint8).reshape(32,24)
        scores=np.frombuffer((args.report/'scores'/f'{stem}.bin').read_bytes(),'<i4')
        assert hashlib.sha256(actual.tobytes()).hexdigest()==row['normalized_sha256']
        assert scores.tolist()==row['scores']
        pb+=int(np.count_nonzero(expected!=actual));sb+=int(np.count_nonzero(scores!=q.logits(expected,model)[0]));count+=1
    result=dict(status='PASS' if count and pb==0 and sb==0 else 'FAIL',characters=count,frames=len(cache),pixel_mismatches=pb,score_mismatches=sb,model_sha256=MODEL_SHA)
    (args.report/'independent_recheck.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
    if result['status']!='PASS':raise AssertionError(result)

if __name__=='__main__':main()
