"""板上边界向量、CRC与失效帧防护；不控制JTAG，不访问COM15。"""
from pathlib import Path
import argparse,hashlib,json,time
import numpy as np,serial
import integer_cnn as q
from norm_ref import normalize_frame,MODEL_SHA
from norm_protocol import upload_frame,recognize,pack_frame,pack_character,BoardError
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--vectors',type=Path,default=ROOT/'sim/fixtures/normalization');args=p.parse_args()
    if hashlib.sha256((ROOT/'model/model.bin').read_bytes()).hexdigest()!=MODEL_SHA:raise ValueError('Frozen model changed')
    folder=args.vectors
    if not (folder/'manifest.json').is_file():p.error(f'Missing normalization inputs: {folder}; use --vectors with a generated frame-vector directory')
    vectors=json.loads((folder/'manifest.json').read_text())
    if not vectors:p.error('Normalization manifest contains no vectors')
    missing=[row['name'] for row in vectors if not (folder/f"{row['name']}.frame.mem").is_file()]
    if missing:p.error(f'Missing frame vectors: {missing}')
    args.out.mkdir(parents=True,exist_ok=False)
    model=q.load(ROOT/'model');rows=[];guards=[];seq=0
    with serial.Serial('COM10',12000000,timeout=.02,write_timeout=3) as stream:
        if hasattr(stream,'set_buffer_size'):stream.set_buffer_size(rx_size=1048576,tx_size=32768)
        stream.reset_input_buffer()
        # 显式取消旧帧，重复执行也能真正验证missing而不只是stale ID。
        stream.write(b'NFR1');time.sleep(.15)
        assert stream.read(16)==b'','Prefix-only upload returned response'
        def rejected(fid,desc,status):
            nonlocal seq
            seq+=1
            try:recognize(stream,seq,fid,desc)
            except BoardError as e:
                if e.status!=status:raise AssertionError((e.status,status))
            else:raise AssertionError('Expected rejection')
        desc=(10,10,10,20,0,0,160,120,0)
        rejected(0,desc,1);guards.append('missing_frame_after_explicit_invalidation')
        for row in vectors:
            name=row['name']
            frame=np.array([int(v,16) for v in (folder/f'{name}.frame.mem').read_text().split()],np.uint8).reshape(120,160)
            seq+=1;fid=upload_frame(stream,seq,frame);seq+=1
            result=recognize(stream,seq,fid,(*row['box'],*row['roi'],row['flags']))
            expected,_=normalize_frame(frame,row['box'],row['roi'],row['flags']);scores=q.logits(expected,model)[0]
            assert np.array_equal(result.pixels,expected),f'{name}: pixels'
            assert np.array_equal(result.scores,scores),f'{name}: scores'
            (args.out/f'{name}.pixels.bin').write_bytes(result.pixels.tobytes())
            (args.out/f'{name}.scores.bin').write_bytes(result.scores.astype('<i4').tobytes())
            rows.append(dict(name=name,compared_pixels=768,compared_scores=36,norm_cycles=result.norm_cycles,cnn_cycles=result.cnn_cycles,
                             frame_sha256=hashlib.sha256(frame.tobytes()).hexdigest(),pixels_sha256=hashlib.sha256(result.pixels.tobytes()).hexdigest()))
        rejected(fid-1,desc,1);guards.append('stale_frame_id')
        rejected(fid,(10,10,0,20,0,0,160,120,0),2);guards.append('zero_width')
        rejected(fid,(150,10,20,20,0,0,160,120,0),2);guards.append('out_of_bounds')
        packet=bytearray(pack_character(seq+1,fid,desc));packet[-1]^=1;stream.write(packet)
        assert stream.read(936)==b'','Bad CRC returned response';guards.append('bad_character_crc')
        # 损坏上传立即取消旧图所有权；不能用部分覆盖过的小图继续识别。
        packet=bytearray(pack_frame(seq+2,frame));packet[-1]^=1;stream.write(packet)
        time.sleep(.05)
        assert stream.read(16)==b'','Bad frame CRC returned response'
        rejected(fid,desc,1);guards.append('bad_upload_invalidates_frame')
        seq+=3;fid=upload_frame(stream,seq,frame)
        stream.write(pack_frame(seq+1,frame)[:1000]);time.sleep(.15)
        assert stream.read(16)==b'','Partial frame returned response'
        rejected(fid,desc,1);guards.append('partial_upload_timeout_invalidates_frame')
        seq+=2;fid=upload_frame(stream,seq,frame);seq+=1
        result=recognize(stream,seq,fid,(*vectors[-1]['box'],*vectors[-1]['roi'],vectors[-1]['flags']))
        assert np.array_equal(result.pixels,expected) and np.array_equal(result.scores,scores)
        guards.append('recovery_after_bad_requests')
    summary=dict(status='PASS',vectors=rows,guards=guards,compared_pixels=len(rows)*768,compared_scores=len(rows)*36,model_sha256=MODEL_SHA)
    (args.out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(json.dumps(summary),flush=True)

if __name__=='__main__':main()
