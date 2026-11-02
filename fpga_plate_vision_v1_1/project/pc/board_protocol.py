"""字符输入/完整分类分数的板测协议。CRC 与序号匹配后才接纳响应。"""
import struct,time,zlib
import numpy as np

def pack_request(sequence,patch):
    a=np.asarray(patch)
    if a.shape!=(32,24) or a.dtype!=np.uint8:raise ValueError('Expected uint8[32,24] character')
    body=b'CNN1'+struct.pack('<I',sequence)+a.tobytes()
    return body+struct.pack('<I',zlib.crc32(body))

def unpack_response(packet,sequence):
    if len(packet)!=160 or packet[:4]!=b'CNR1':raise ValueError('Invalid CNN response header/size')
    if zlib.crc32(packet[:-4])!=struct.unpack('<I',packet[-4:])[0]:raise ValueError('CNN response CRC mismatch')
    seq,cycles=struct.unpack('<II',packet[4:12])
    if seq!=sequence:raise ValueError(f'Unexpected response sequence {seq} != {sequence}')
    return cycles,np.frombuffer(packet[12:156],dtype='<i4').copy()

def transact(stream,sequence,patch,timeout=3):
    request=pack_request(sequence,patch)
    if stream.write(request)!=len(request):raise IOError('Incomplete UART write')
    deadline=time.monotonic()+timeout;buffer=bytearray()
    while time.monotonic()<deadline:
        buffer.extend(stream.read(stream.in_waiting or 1))
        index=buffer.find(b'CNR1')
        if index<0:
            if len(buffer)>3:del buffer[:-3]
            continue
        if index:del buffer[:index]
        if len(buffer)>=160:return unpack_response(bytes(buffer[:160]),sequence)
    raise TimeoutError(f'No complete CNN response for sequence {sequence}')
