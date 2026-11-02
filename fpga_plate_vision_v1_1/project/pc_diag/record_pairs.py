from pathlib import Path
import argparse,json,re,time,sys
import numpy as np
from PIL import Image,ImageDraw
import serial
from pair_protocol import Parser
def main():
 p=argparse.ArgumentParser();p.add_argument('--port',default='COM10');p.add_argument('--frames',type=int,default=300);p.add_argument('--label',required=True);p.add_argument('--reference-bars',action='store_true');p.add_argument('--show',action='store_true');p.add_argument('--timeout',type=float,default=90)
 args=p.parse_args()
 if args.port.upper()=='COM15':raise SystemExit('COM15 is excluded from this task')
 if not re.fullmatch('[A-Za-z0-9_-]+',args.label):raise SystemExit('Unique safe label required')
 root=Path(__file__).resolve().parents[1];out=root/'reports/uart_pairs'/args.label;out.mkdir(parents=True,exist_ok=False)
 frames_dir=out/'frames';frames_dir.mkdir()
 expected=np.load(Path(__file__).with_name('bars_reference.npy')) if args.reference_bars else None
 parser=Parser();count=bad=source_gaps=0;previous=None;dropped=0;started=time.monotonic();last_frame_time=started;reason='UNKNOWN';times=[]
 cv2=None
 if args.show:
  import cv2
 try:
  with serial.Serial(args.port,12000000,timeout=.1) as stream,(out/'wire.bin').open('wb') as wire,(out/'frames.jsonl').open('w') as log:
   if hasattr(stream,'set_buffer_size'):stream.set_buffer_size(rx_size=1048576,tx_size=4096)
   stream.reset_input_buffer()
   print(f'PAIR_RECORDING {args.port} 12000000 baud label={args.label}',flush=True)
   while True:
    data=stream.read(stream.in_waiting or 16384)
    if data:wire.write(data)
    for f in parser.feed(data):
     count+=1;last_frame_time=time.monotonic()
     a=np.frombuffer(f.pixels,np.uint8).reshape(f.height,f.width,2)
     if previous is not None and f.frame_id>previous+1:source_gaps+=f.frame_id-previous-1
     previous=f.frame_id;dropped=f.dropped;times.append(f.tick)
     prefix=f'seq_{count:06d}_src_{f.frame_id:08d}'
     (frames_dir/f'{prefix}.bin').write_bytes(f.pixels)
     Image.fromarray(a[:,:,0]).save(frames_dir/f'{prefix}_selected.png')
     Image.fromarray(a[:,:,1]).save(frames_dir/f'{prefix}_other.png')
     p0_bad=p1_bad=None
     if expected is not None:
      assert a.shape==expected.shape
      p0_bad=int(np.count_nonzero(a[:,:,0]!=expected[:,:,0]));p1_bad=int(np.count_nonzero(a[:,:,1]!=expected[:,:,1]));bad+=int(p0_bad!=0 or p1_bad!=0)
     line=dict(seq=count,frame_id=f.frame_id,tick=f.tick,dropped=f.dropped,crc=f'{f.crc:08x}',p0_mismatches=p0_bad,p1_mismatches=p1_bad,elapsed_ms=round(1000*(time.monotonic()-started)),file=prefix)
     log.write(json.dumps(line)+'\n');log.flush()
     preview=np.concatenate((a[:,:,0],a[:,:,1]),axis=1)
     tmp=out/'latest.tmp.png';Image.fromarray(preview).save(tmp);tmp.replace(out/'latest.png')
     if cv2 is not None:
      shown=cv2.resize(preview,None,fx=3,fy=3,interpolation=cv2.INTER_NEAREST)
      cv2.imshow('FIFO diagnostic: selected | preceding byte (PC preview only)',shown)
      if cv2.waitKey(1)&255==ord('q'):reason='USER_STOP';break
     if count%50==0 or count==1:print(f'PAIR_FRAME count={count} source={f.frame_id} fpga_drop={dropped} packet_crc_errors={parser.payload_errors} reference_bad={bad}',flush=True)
     if args.frames and count>=args.frames:reason='FRAME_TARGET';break
    if reason in ('FRAME_TARGET','USER_STOP'):break
    if (out/'stop.flag').exists():reason='HOST_STOP';break
    if time.monotonic()-last_frame_time>args.timeout:reason='NO_VALID_FRAME_TIMEOUT';break
 except Exception as e:
  reason='ERROR';(out/'error.txt').write_text(repr(e));print(repr(e),flush=True)
 finally:
  if cv2 is not None:cv2.destroyAllWindows()
  fps=None
  if len(times)>1:
   deltas=[(b-a)&0xffffffff for a,b in zip(times,times[1:]) if b!=a]
   if deltas:fps=100000000/float(np.median(deltas))
  result=dict(reason=reason,frames=count,reference_checked=bool(args.reference_bars),reference_bad_frames=bad,fpga_diagnostic_dropped=dropped,header_crc_errors=parser.header_errors,payload_crc_errors=parser.payload_errors,source_frame_id_gaps=source_gaps,median_source_fps=fps,duration_sec=time.monotonic()-started)
  (out/'summary.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
 return 0 if reason in ('FRAME_TARGET','USER_STOP','HOST_STOP') else 1
if __name__=='__main__':raise SystemExit(main())
