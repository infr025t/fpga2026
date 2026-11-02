"""实板检查坏CRC/半包不启动、超时后下一有效请求仍逐分数正确。"""
from pathlib import Path
import json,time
import numpy as np,serial
from board_protocol import pack_request,transact
import integer_cnn as q
ROOT=Path(__file__).resolve().parents[1]

def main():
    out=ROOT/'reports/board/protocol_guards';out.mkdir(parents=True,exist_ok=False)
    patch=np.load(ROOT/'sim/vectors.npz')['inputs'][9]
    expected=q.logits(patch,q.load(ROOT/'model'))[0]
    events=[]
    try:
        with serial.Serial('COM10',12000000,timeout=.2,write_timeout=2) as stream:
            stream.reset_input_buffer()
            bad=bytearray(pack_request(9001,patch));bad[-1]^=1;stream.write(bad)
            response=stream.read(160)
            if response:raise AssertionError('Unexpected response to corrupt request')
            events.append('corrupt_crc_no_response')
            stream.write(pack_request(9002,patch)[:80])
            response=stream.read(160)
            if response:raise AssertionError('Unexpected response to partial request')
            events.append('partial_packet_timeout_no_response')
            cycles,scores=transact(stream,9003,patch)
            np.testing.assert_array_equal(scores,expected)
            events.append('valid_after_timeout_all36_match')
        result=dict(status='PASS',events=events,cycles=cycles)
    except Exception as e:
        result=dict(status='FAIL',events=events,error=repr(e));raise
    finally:
        (out/'summary.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))

if __name__=='__main__':main()
