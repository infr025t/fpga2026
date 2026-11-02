"""PC仅前处理；FPGA计算36分数；软件参考只用于核验，不替代板上结果。"""
from pathlib import Path
import argparse,collections,hashlib,json,time
import cv2,numpy as np,serial
import integer_cnn as q
from frontend import segment,feature_patch,CLASSES
from board_protocol import transact

ROOT=Path(__file__).resolve().parents[1]
MODEL_SHA='179d6d9b9a4e2229c152770152fe6c8d71ff924af5d9da06132debd730cf4645'

def main():
    p=argparse.ArgumentParser();p.add_argument('--frames',type=Path);p.add_argument('--limit',type=int,default=100)
    p.add_argument('--roi',nargs=4,type=int,default=[26,35,158,87]);p.add_argument('--rotation',type=int,choices=[0,180],default=0)
    p.add_argument('--invert',action='store_true');p.add_argument('--out',type=Path,required=True);p.add_argument('--truth')
    p.add_argument('--port',default='COM10');args=p.parse_args()
    if args.port.upper()=='COM15':p.error('COM15 excluded')
    if args.limit<=0:p.error('--limit must be positive')
    x0,y0,x1,y1=args.roi
    if not(0<=x0<x1<=160 and 0<=y0<y1<=120):p.error('ROI must be inside160x120')
    if hashlib.sha256((ROOT/'model/model.bin').read_bytes()).hexdigest()!=MODEL_SHA:raise ValueError('Frozen model hash mismatch')
    model=q.load(ROOT/'model');jobs=[]
    if args.frames:
        files=sorted(args.frames.glob('*selected.png'))[:args.limit]
        if not files:raise ValueError('No input frames')
        for file in files:
            a=cv2.imread(str(file),0)
            if a is None or a.shape!=(120,160):raise ValueError(f'Invalid image {file}')
            if args.rotation:a=cv2.rotate(a,cv2.ROTATE_180)
            if args.invert:a=255-a
            crop=a[y0:y1,x0:x1];boxes=segment(crop)
            patches=[feature_patch(crop,b,(24,32),'gray') for b in boxes]
            jobs.append((str(file),patches,boxes,hashlib.sha256(file.read_bytes()).hexdigest()))
    else:
        vectors=np.load(ROOT/'sim/vectors.npz')
        jobs=[(f'vector_{i}',[v],[],None) for i,v in enumerate(vectors['inputs'])]
    args.out.mkdir(parents=True,exist_ok=False)
    (args.out/'inputs').mkdir()
    results=[];durations=[];cycles_all=[];sequence=0;score_mismatches=0
    started=time.monotonic()
    # 打开与关闭仅限指定COM10，不改FPGA/Flash，不自动改变开关。
    try:
        if not any(patches for _,patches,_,_ in jobs):raise ValueError('No characters segmented; no FPGA inference was performed')
        with serial.Serial(args.port,12000000,timeout=.02,write_timeout=2) as stream,(args.out/'characters.jsonl').open('w',encoding='utf-8') as log:
            if hasattr(stream,'set_buffer_size'):stream.set_buffer_size(rx_size=1048576,tx_size=4096)
            stream.reset_input_buffer()
            for source,patches,boxes,source_hash in jobs:
                predicted='';expected=''
                for i,patch in enumerate(patches):
                    sequence+=1;before=time.monotonic();cycles,actual=transact(stream,sequence,patch)
                    durations.append(time.monotonic()-before);cycles_all.append(cycles)
                    reference=q.logits(patch,model)[0]
                    mismatch=int(np.count_nonzero(actual!=reference));score_mismatches+=mismatch
                    text=CLASSES[int(actual.argmax())];predicted+=text;expected+=CLASSES[int(reference.argmax())]
                    input_file=args.out/'inputs'/f'{sequence:06d}.bin';input_file.write_bytes(patch.tobytes())
                    row=dict(sequence=sequence,source=source,character_index=i,fpga_prediction=text,fpga_cycles=cycles,
                             scores=actual.tolist(),reference_scores=reference.tolist(),score_mismatches=mismatch,
                             input_sha256=hashlib.sha256(patch.tobytes()).hexdigest())
                    log.write(json.dumps(row)+'\n');log.flush()
                    if mismatch:raise AssertionError(f'FPGA score mismatch: sequence{sequence}, {mismatch}/36 scores')
                row=dict(source=source,source_sha256=source_hash,prediction=predicted,reference_prediction=expected,boxes=boxes)
                results.append(row)
                if len(results)==1 or len(results)%10==0:print(json.dumps(dict(completed=len(results),characters=sequence,last=predicted)),flush=True)
        summary=dict(status='PASS' if sequence>0 else 'NO_CHARACTERS',frames=len(results),characters=sequence,compared_scores=sequence*36,
                     score_mismatches=score_mismatches,model_sha256=MODEL_SHA,roi=args.roi,rotation=args.rotation,invert=args.invert,
                     predictions=dict(collections.Counter(r['prediction'] for r in results)),min_cycles=min(cycles_all,default=None),
                     max_cycles=max(cycles_all,default=None),median_uart_roundtrip_ms=round(float(np.median(durations))*1000,3) if durations else None,
                     elapsed_sec=time.monotonic()-started,scope='FPGA CNN; PC segmentation and normalization; no automatic FPGA localization')
        if args.truth is not None:summary.update(truth=args.truth,exact_correct=sum(r['prediction']==args.truth for r in results))
    except Exception as e:
        summary=dict(status='FAIL',error=repr(e),completed_frames=len(results),characters=sequence,score_mismatches=score_mismatches,model_sha256=MODEL_SHA)
        raise
    finally:
        (args.out/'frames.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        if 'summary' in locals():(args.out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(json.dumps(summary),flush=True)

if __name__=='__main__':main()
