"""NFR1/NCH1/NSG1停止等待协议；调用方提供串口流，本模块不打开COM。"""
from dataclasses import dataclass
import operator
import struct
import time
import zlib
import numpy as np

class BoardError(RuntimeError):
    def __init__(self,status):
        self.status=status
        super().__init__({1:'Missing or stale frame',2:'Invalid normalization descriptor',3:'Worker watchdog expired',4:'Segmentation resource overflow or incomplete boxes'}.get(status,f'Board status {status}'))

@dataclass(frozen=True)
class NormResult:
    pixels: np.ndarray
    scores: np.ndarray
    norm_cycles: int
    cnn_cycles: int

@dataclass(frozen=True)
class SegmentResult:
    boxes: list[tuple[int, int, int, int]]
    cycles: int

def pack_segment(sequence,frame_id,roi,flags=0):
    bounds=tuple(_uint(v,8) for v in roi)
    flags=_uint(flags,8)
    if len(bounds)!=4 or flags>3: raise ValueError('Expected four ROI bytes, flags 0..3')
    return _crc(b'NSG1'+struct.pack('<II',_uint(sequence,32),_uint(frame_id,32))+bytes(bounds)+bytes([flags]))

def unpack_segment_result(packet,sequence):
    _check(packet,b'NSR1',280,sequence)
    cycles,count=struct.unpack_from('<II',packet,12)
    if count>64: raise ValueError('Segment box count exceeds 64')
    if any(packet[20+count*4:276]): raise ValueError('Nonzero unused segment slots')
    boxes=[tuple(packet[20+i*4:24+i*4]) for i in range(count)]
    return SegmentResult(boxes,cycles)

def segment(stream,sequence,frame_id,roi,flags=0,timeout=5):
    return unpack_segment_result(_exchange(stream,pack_segment(sequence,frame_id,roi,flags),b'NSR1',280,timeout),sequence)

def _uint(value,bits):
    try: value=operator.index(value)
    except TypeError: raise ValueError('integer required') from None
    if not 0<=value<(1<<bits): raise ValueError(f'uint{bits} out of range')
    return value

def _crc(body): return body+struct.pack('<I',zlib.crc32(body))

def pack_frame(sequence,frame):
    a=np.asarray(frame)
    if a.shape!=(120,160) or a.dtype!=np.uint8: raise ValueError('Expected uint8[120,160] frame')
    return _crc(b'NFR1'+struct.pack('<I',_uint(sequence,32))+a.tobytes())

def pack_character(sequence,frame_id,descriptor):
    d=tuple(_uint(v,8) for v in descriptor)
    if len(d)!=9 or d[8]>3: raise ValueError('Expected nine descriptor bytes, flags 0..3')
    return _crc(b'NCH1'+struct.pack('<II',_uint(sequence,32),_uint(frame_id,32))+bytes(d))

def _check(packet,magic,size,sequence):
    if len(packet)!=size or packet[:4]!=magic: raise ValueError('Invalid response header/size')
    if zlib.crc32(packet[:-4])!=struct.unpack('<I',packet[-4:])[0]: raise ValueError('Response CRC mismatch')
    seq,status=struct.unpack_from('<II',packet,4)
    if seq!=sequence: raise ValueError(f'Unexpected response sequence {seq} != {sequence}')
    if status: raise BoardError(status)

def unpack_ack(packet,sequence):
    _check(packet,b'NFA1',16,sequence)
    return sequence

def unpack_result(packet,sequence):
    _check(packet,b'NRS1',936,sequence)
    nc,cc=struct.unpack_from('<II',packet,12)
    return NormResult(np.frombuffer(packet[20:788],dtype=np.uint8).reshape(32,24).copy(),np.frombuffer(packet[788:932],dtype='<i4').copy(),nc,cc)

def _exchange(stream,request,magic,size,timeout):
    # read必须有有限超时（例如serial.Serial(timeout=0.05)），才能保障整体deadline。
    if timeout<=0: raise ValueError('positive timeout required')
    deadline=time.monotonic()+timeout
    if stream.write(request)!=len(request): raise IOError('Incomplete UART write')
    buffer=bytearray()
    while time.monotonic()<deadline:
        # 限定本次读取，防止吞掉后续响应；协议要求调用方停止等待。
        waiting=getattr(stream,'in_waiting',0)
        buffer.extend(stream.read(max(1,min(waiting,size-len(buffer)))))
        index=buffer.find(magic)
        if index<0:
            if len(buffer)>3: del buffer[:-3]
            continue
        if index: del buffer[:index]
        if len(buffer)>=size: return bytes(buffer[:size])
    raise TimeoutError('No complete normalization response')

def upload_frame(stream,sequence,frame,timeout=3):
    return unpack_ack(_exchange(stream,pack_frame(sequence,frame),b'NFA1',16,timeout),sequence)

def recognize(stream,sequence,frame_id,descriptor,timeout=5):
    return unpack_result(_exchange(stream,pack_character(sequence,frame_id,descriptor),b'NRS1',936,timeout),sequence)
