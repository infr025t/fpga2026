"""只发送原图和固定ROI；使用FPGA返回的框完成识别，参考算法只做事后核验。"""
from pathlib import Path
import argparse,collections,hashlib,json,time
import cv2,numpy as np,serial
import integer_cnn as q
from frontend import CLASSES
from norm_ref import normalize_frame,MODEL_SHA
from norm_protocol import upload_frame,segment,recognize
from segment_ref import segment_frame
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('--frames',type=Path,required=True);p.add_argument('--limit',type=int,default=100)
    p.add_argument('--roi',nargs=4,type=int,default=[26,35,158,87]);p.add_argument('--rotation',type=int,choices=[0,180],default=0)
    p.add_argument('--invert',action='store_true');p.add_argument('--truth');p.add_argument('--out',type=Path,required=True)
    args=p.parse_args()
    if args.limit<=0:p.error('positive limit required')
    x0,y0,x1,y1=args.roi
    if not(0<=x0<x1<=160 and 0<=y0<y1<=120):p.error('ROI outside160x120')
    if hashlib.sha256((ROOT/'model/model.bin').read_bytes()).hexdigest()!=MODEL_SHA:raise ValueError('Frozen model changed')
    files=sorted(args.frames.glob('*selected.png'))[:args.limit]
    if not files:raise ValueError('No selected frame files')
    args.out.mkdir(parents=True,exist_ok=False)
    for folder in ('frames_raw','normalized','scores'):(args.out/folder).mkdir()
    model=q.load(ROOT/'model');flags=int(bool(args.rotation))|int(args.invert)<<1
    seq=characters=pb=sb=box_bad=0;frames=[];seg_cycles=[];norm_cycles=[];cnn_cycles=[];started=time.monotonic();summary={'status':'INCOMPLETE'}
    try:
        with serial.Serial('COM10',12000000,timeout=.02,write_timeout=3) as stream,(args.out/'characters.jsonl').open('w',encoding='utf-8') as log:
            if hasattr(stream,'set_buffer_size'):stream.set_buffer_size(rx_size=1048576,tx_size=32768)
            stream.reset_input_buffer()
            for fi,file in enumerate(files,1):
                raw=cv2.imread(str(file),0)
                if raw is None or raw.shape!=(120,160):raise ValueError(str(file))
                (args.out/'frames_raw'/f'{fi:04d}.bin').write_bytes(raw.tobytes())
                seq+=1;fid=upload_frame(stream,seq,raw)
                seq+=1;detected=segment(stream,seq,fid,args.roi,flags)
                # 到此FPGA已独立得出框；下述参考只判定结果，不选框、不提供候选答案。
                reference=segment_frame(raw,args.roi,flags)
                boxes=[tuple(b) for b in detected.boxes]
                seg_cycles.append(detected.cycles)
                mismatch=reference['status']!=0 or boxes!=reference['boxes'];box_bad+=int(mismatch)
                frame_row=dict(frame_index=fi,source=str(file),source_sha256=hashlib.sha256(file.read_bytes()).hexdigest(),
                               raw_sha256=hashlib.sha256(raw.tobytes()).hexdigest(),frame_id=fid,roi=args.roi,flags=flags,
                               fpga_boxes=boxes,reference_boxes=reference['boxes'],box_mismatch=bool(mismatch),seg_cycles=detected.cycles)
                frames.append(frame_row)
                if mismatch:raise AssertionError(f'Frame{fi}: boxes mismatch {boxes} vs {reference}')
                prediction=''
                for ci,box in enumerate(boxes):
                    descriptor=(*box,*args.roi,flags)
                    seq+=1;result=recognize(stream,seq,fid,descriptor)
                    expected,meta=normalize_frame(raw,box,args.roi,flags);scores=q.logits(expected,model)[0]
                    pm=int(np.count_nonzero(result.pixels!=expected));sm=int(np.count_nonzero(result.scores!=scores));pb+=pm;sb+=sm;characters+=1
                    norm_cycles.append(result.norm_cycles);cnn_cycles.append(result.cnn_cycles)
                    ch=CLASSES[int(result.scores.argmax())];prediction+=ch;stem=f'{seq:06d}'
                    (args.out/'normalized'/f'{stem}.bin').write_bytes(result.pixels.tobytes())
                    (args.out/'scores'/f'{stem}.bin').write_bytes(result.scores.astype('<i4').tobytes())
                    row=dict(sequence=seq,frame_index=fi,frame_id=fid,character_index=ci,descriptor=descriptor,prediction=ch,
                             norm_cycles=result.norm_cycles,cnn_cycles=result.cnn_cycles,pixel_mismatches=pm,score_mismatches=sm,
                             normalized_sha256=hashlib.sha256(result.pixels.tobytes()).hexdigest(),parameters=meta,
                             scores=result.scores.tolist(),reference_scores=scores.tolist())
                    log.write(json.dumps(row)+'\n');log.flush()
                    if pm or sm:raise AssertionError(f'Seq{seq}: pixel{pm}, score{sm} mismatches')
                frame_row['prediction']=prediction
                if fi==1 or fi%10==0:print(json.dumps(dict(frames=fi,characters=characters,prediction=prediction,seg_cycles=detected.cycles)),flush=True)
        if not characters:raise AssertionError('No recognized characters in this quality test')
        summary=dict(status='PASS',frames=len(frames),characters=characters,box_mismatched_frames=box_bad,pixel_mismatches=pb,score_mismatches=sb,
                     compared_pixels=characters*768,compared_scores=characters*36,predictions=dict(collections.Counter(f['prediction'] for f in frames)),
                     min_seg_cycles=min(seg_cycles),max_seg_cycles=max(seg_cycles),min_norm_cycles=min(norm_cycles),max_norm_cycles=max(norm_cycles),
                     min_cnn_cycles=min(cnn_cycles),max_cnn_cycles=max(cnn_cycles),elapsed_sec=time.monotonic()-started,model_sha256=MODEL_SHA,
                     roi=args.roi,flags=flags,scope='FPGA segmentation+normalization+CNN; PC sends fixed ROI/raw image and schedules requests; argmax display on PC')
        if args.truth is not None:summary.update(truth_for_scoring_only=args.truth,exact_correct=sum(f['prediction']==args.truth for f in frames))
    except Exception as e:
        summary=dict(status='FAIL',error=repr(e),frames=len(frames),characters=characters,box_mismatched_frames=box_bad,pixel_mismatches=pb,score_mismatches=sb)
        raise
    finally:
        (args.out/'frames.json').write_text(json.dumps(frames,indent=2),encoding='utf-8')
        (args.out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(json.dumps(summary),flush=True)

if __name__=='__main__':main()
