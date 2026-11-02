"""板上分割向量与失效帧保护；含空ROI内容/65候选溢出，不要求有字符。"""
from pathlib import Path
import argparse,hashlib,json,time
import numpy as np,serial
from norm_protocol import upload_frame,segment,pack_segment,BoardError
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);args=p.parse_args()
    folder=ROOT/'reports/segmentation_reference/vectors'
    # 向量目录由参考生成器固定；存在性检查避免以空测试宣称通过。
    if not (folder/'manifest.json').exists():folder=ROOT/'reports/segmentation_reference/rtl_vectors'
    cases=json.loads((folder/'manifest.json').read_text())
    if not cases:raise ValueError('No test vectors')
    args.out.mkdir(parents=True,exist_ok=False);seq=0;rows=[];guards=[]
    with serial.Serial('COM10',12000000,timeout=.02,write_timeout=3) as stream:
        if hasattr(stream,'set_buffer_size'):stream.set_buffer_size(rx_size=1048576,tx_size=32768)
        stream.reset_input_buffer();stream.write(b'NFR1');time.sleep(.15)
        assert stream.read(16)==b''
        def reject(fid,roi,status):
            nonlocal seq
            seq+=1
            try:segment(stream,seq,fid,roi)
            except BoardError as e:assert e.status==status,(e.status,status)
            else:raise AssertionError('Expected rejection')
        reject(0,(0,0,160,120),1);guards.append('no_frame')
        for case in cases:
            name=case['name'];frame=np.array([int(v,16) for v in (folder/f'{name}.frame.mem').read_text().split()],np.uint8).reshape(120,160)
            assert hashlib.sha256(frame.tobytes()).hexdigest()==case['input_sha256']
            seq+=1;fid=upload_frame(stream,seq,frame);seq+=1
            try:
                result=segment(stream,seq,fid,case['roi'],case['flags']);actual=[tuple(b) for b in result.boxes]
                assert case['status']==0,(name,'unexpected success')
                assert actual==[tuple(b) for b in case['boxes']],(name,actual,case['boxes'])
                rows.append(dict(name=name,status=0,boxes=actual,cycles=result.cycles))
            except BoardError as e:
                expected={1:2,2:4,3:4}.get(case['status'])
                assert e.status==expected,(name,e.status,expected)
                rows.append(dict(name=name,status=e.status,boxes=[]))
        reject(fid-1,(0,0,160,120),1);guards.append('stale_frame')
        packet=bytearray(pack_segment(seq+1,fid,(0,0,160,120),0));packet[-1]^=1;stream.write(packet)
        assert stream.read(280)==b'';guards.append('bad_seg_crc')
        stream.write(pack_segment(seq+2,fid,(0,0,160,120),0)[:14]);time.sleep(.15)
        assert stream.read(280)==b'';guards.append('partial_seg_timeout')
        # 最后一例虽然ROI非法，上传帧仍有效；合法ROI可重新运行。
        seq+=3;recovered=segment(stream,seq,fid,(0,0,1,1),0)
        assert recovered.boxes==[];guards.append('recovery_on_valid_frame')
    summary=dict(status='PASS',vectors=len(rows),cases=rows,guards=guards)
    (args.out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(json.dumps(summary),flush=True)

if __name__=='__main__':main()
