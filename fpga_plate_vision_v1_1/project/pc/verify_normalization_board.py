"""PC只定位；上传原灰度小图，逐像素核验板上归一化及全部CNN分数。"""
from pathlib import Path
import argparse,collections,hashlib,json,time
import cv2,numpy as np,serial
import integer_cnn as q
from frontend import segment,feature_patch,CLASSES
from norm_ref import feature_patch_int,MODEL_SHA
from norm_protocol import upload_frame,recognize

ROOT=Path(__file__).resolve().parents[1]

def prepare(image,roi,rotation,invert):
    if image.shape!=(120,160) or image.dtype!=np.uint8:raise ValueError('Expected uint8 160x120 image')
    logical=image[::-1,::-1] if rotation else image
    if invert:logical=255-logical
    x0,y0,x1,y1=roi
    crop=logical[y0:y1,x0:x1]
    boxes=segment(crop)
    result=[]
    for box in boxes:
        x,y,w,h=box
        absolute=(x+x0,y+y0,w,h)
        expected,meta=feature_patch_int(logical,absolute,roi)
        legacy=feature_patch(crop,box,(24,32),'gray')
        result.append(((*absolute,*roi,int(bool(rotation))|int(invert)<<1),expected,legacy,meta))
    return result

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--frames',type=Path,required=True);p.add_argument('--limit',type=int,default=100)
    p.add_argument('--roi',nargs=4,type=int,default=[26,35,158,87]);p.add_argument('--rotation',type=int,choices=[0,180],default=0)
    p.add_argument('--invert',action='store_true');p.add_argument('--truth');p.add_argument('--out',type=Path,required=True)
    p.add_argument('--port',default='COM10');args=p.parse_args()
    if args.port.upper()=='COM15':p.error('COM15 excluded')
    if args.limit<=0:p.error('limit must be positive')
    x0,y0,x1,y1=args.roi
    if not(0<=x0<x1<=160 and 0<=y0<y1<=120):p.error('ROI outside160x120')
    model_hash=hashlib.sha256((ROOT/'model/model.bin').read_bytes()).hexdigest()
    if model_hash!=MODEL_SHA:raise ValueError('Frozen model changed')
    files=sorted(args.frames.glob('*selected.png'))[:args.limit]
    if not files:raise ValueError('No selected input frames')
    jobs=[]
    for file in files:
        image=cv2.imread(str(file),0)
        if image is None:raise ValueError(str(file))
        jobs.append((file,image,prepare(image,args.roi,args.rotation,args.invert)))
    if not any(parts for _,_,parts in jobs):raise ValueError('No segmented characters; no inference performed')
    model=q.load(ROOT/'model');args.out.mkdir(parents=True,exist_ok=False)
    for folder in ('frames_raw','normalized','scores'): (args.out/folder).mkdir()
    rows=[];characters=0;pixel_bad=score_bad=0;norm_cycles=[];cnn_cycles=[];durations=[];sequence=0
    summary={'status':'INCOMPLETE'};started=time.monotonic()
    try:
        with serial.Serial(args.port,12000000,timeout=.02,write_timeout=3) as stream,(args.out/'characters.jsonl').open('w',encoding='utf-8') as log:
            if hasattr(stream,'set_buffer_size'):stream.set_buffer_size(rx_size=1048576,tx_size=32768)
            stream.reset_input_buffer()
            for index,(source,image,parts) in enumerate(jobs,1):
                sequence+=1;frame_id=upload_frame(stream,sequence,image)
                raw_file=args.out/'frames_raw'/f'{index:04d}.bin';raw_file.write_bytes(image.tobytes())
                prediction='';reference_prediction='';legacy_prediction=''
                for ci,(descriptor,expected,legacy,meta) in enumerate(parts):
                    sequence+=1;before=time.monotonic()
                    actual=recognize(stream,sequence,frame_id,descriptor)
                    durations.append(time.monotonic()-before)
                    scores=q.logits(expected,model)[0];legacy_scores=q.logits(legacy,model)[0]
                    pb=int(np.count_nonzero(actual.pixels!=expected));sb=int(np.count_nonzero(actual.scores!=scores))
                    pixel_bad+=pb;score_bad+=sb;characters+=1
                    norm_cycles.append(actual.norm_cycles);cnn_cycles.append(actual.cnn_cycles)
                    ch=CLASSES[int(actual.scores.argmax())];prediction+=ch
                    reference_prediction+=CLASSES[int(scores.argmax())];legacy_prediction+=CLASSES[int(legacy_scores.argmax())]
                    stem=f'{sequence:06d}'
                    (args.out/'normalized'/f'{stem}.bin').write_bytes(actual.pixels.tobytes())
                    (args.out/'scores'/f'{stem}.bin').write_bytes(actual.scores.astype('<i4').tobytes())
                    row=dict(sequence=sequence,frame_index=index,frame_id=frame_id,character_index=ci,descriptor=descriptor,
                             norm_cycles=actual.norm_cycles,cnn_cycles=actual.cnn_cycles,pixel_mismatches=pb,score_mismatches=sb,
                             prediction=ch,parameters=meta,normalized_sha256=hashlib.sha256(actual.pixels.tobytes()).hexdigest(),
                             scores=actual.scores.tolist(),reference_scores=scores.tolist())
                    log.write(json.dumps(row)+'\n');log.flush()
                    if pb or sb:raise AssertionError(f'seq{sequence}: pixel{pb}, score{sb} mismatches')
                rows.append(dict(source=str(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),raw_sha256=hashlib.sha256(image.tobytes()).hexdigest(),
                                 prediction=prediction,reference_prediction=reference_prediction,legacy_prediction=legacy_prediction,characters=len(parts)))
                if index==1 or index%10==0:print(json.dumps(dict(frames=index,characters=characters,last=prediction)),flush=True)
        summary=dict(status='PASS',frames=len(rows),characters=characters,compared_pixels=characters*768,compared_scores=characters*36,
                     pixel_mismatches=pixel_bad,score_mismatches=score_bad,predictions=dict(collections.Counter(r['prediction'] for r in rows)),
                     changed_vs_legacy=sum(r['prediction']!=r['legacy_prediction'] for r in rows),
                     min_norm_cycles=min(norm_cycles),max_norm_cycles=max(norm_cycles),min_cnn_cycles=min(cnn_cycles),max_cnn_cycles=max(cnn_cycles),
                     median_roundtrip_ms=1000*float(np.median(durations)),elapsed_sec=time.monotonic()-started,
                     model_sha256=model_hash,roi=args.roi,rotation=args.rotation,invert=args.invert,
                     scope='FPGA normalization+CNN; PC segmentation and raw-frame transport; stored inputs are regression, not blind recognition validation')
        if args.truth is not None:summary.update(truth_for_scoring_only=args.truth,exact_correct=sum(r['prediction']==args.truth for r in rows))
    except Exception as e:
        summary=dict(status='FAIL',error=repr(e),frames=len(rows),characters=characters,pixel_mismatches=pixel_bad,score_mismatches=score_bad)
        raise
    finally:
        (args.out/'frames.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
        (args.out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(json.dumps(summary),flush=True)

if __name__=='__main__':main()
