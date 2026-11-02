"""校验 xsim 从 UART 引脚采样的字节，不读取 DUT 内部存储。"""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'pc'))
from auto_protocol import StreamParser

raw = bytes.fromhex(Path(sys.argv[1]).read_text())
parser = StreamParser()
packets = []
for start in range(0, len(raw), 257):
    packets += parser.feed(raw[start:start+257])
assert [(p['magic'],p['frame_id']) for p in packets] == [
    ('AIF1',1),('ASG1',1),('ACR2',1),('ACR2',1),('AER1',1),('AER1',3),('AER1',5),('AER1',7),('AER1',8),('AER1',10)] + [('ASG1',11)]*7 + [('AER1',12)]
frame,seg,char,char2,result = packets[:5]
assert frame['raw'] == bytes(i%256 for i in range(19200))
assert frame['capture_tick'] == 123 and frame['roi'] == (26,35,158,87)
assert seg['boxes'] == [(26,35,12,24),(42,35,12,24)] and seg['seg_cycles'] == 1234
assert char['norm'] == bytes((i*3)%256 for i in range(768))
assert char['scores'] == list(range(-100,-64))
assert char['norm_cycles'] == 4567 and char['core_cycles'] == 8901 and char['ascii'] == ord('Z')
assert char2['norm'] == bytes((i*3+1)%256 for i in range(768))
assert char2['scores'] == list(range(-200,-164)) and char2['char_index'] == 1 and char2['box'] == (42,35,12,24)
assert result['text'] == b'ZZ' and result['publisher_dropped'] == 0
assert packets[8]['status'] == 1 and packets[8]['completed_chars'] == 0
assert packets[9]['publisher_dropped'] == 5
assert packets[-1]['publisher_dropped'] == 6
print(f'PASS UART Python oracle: {len(raw)} pin-sampled bytes, {len(packets)} CRC-valid packets; continuous chars, invalid EOF, FIFO overflow, pending collision and worker error recovered')
