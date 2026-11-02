"""被动串口协议解码；不发送命令。CRC 错误或截断后扫描下一完整有效包。"""
import struct
import zlib

LENGTHS = {b'AIF1': 19228, b'ASG1': 280, b'ASG2': 284, b'ASG3': 284, b'ASG4': 284, b'ASG5': 284, b'ACR2': 944, b'AER1': 100}

def decode_packet(data):
    magic = data[:4]
    if magic not in LENGTHS or len(data) != LENGTHS[magic]:
        raise ValueError('packet length/magic')
    u32 = lambda offset: struct.unpack_from('<I', data, offset)[0]
    if zlib.crc32(data[:-4]) != u32(len(data)-4):
        raise ValueError('packet CRC')
    result = {'magic': magic.decode(), 'type': magic.decode(), 'frame_id': u32(4)}
    if magic == b'AIF1':
        if data[16] > 3 or any(data[17:20]):
            raise ValueError('frame flags/reserved')
        roi = tuple(data[12:16])
        if not (roi[0] < roi[2] <= 160 and roi[1] < roi[3] <= 120):
            raise ValueError('ROI')
        raw = data[20:19220]
        if zlib.crc32(raw) != u32(19220):
            raise ValueError('raw CRC')
        result.update(capture_tick=u32(8), roi=roi, flags=data[16], raw=raw, raw_crc=u32(19220))
    elif magic in (b'ASG1',b'ASG2',b'ASG3',b'ASG4',b'ASG5'):
        count = u32(16)
        start=20 if magic==b'ASG1' else 24
        if count > 64 or u32(8) > 255 or any(data[start+count*4:start+256]):
            raise ValueError('segment fields')
        if magic!=b'ASG1':
            roi=tuple(data[20:24])
            if not ((roi==(0,0,0,0) and count==0) or (roi[0]<roi[2]<=160 and roi[1]<roi[3]<=120)):
                raise ValueError('located ROI')
            result['roi']=roi
        boxes = [tuple(data[start+i*4:start+4+i*4]) for i in range(count)]
        if any(not (w and h and x+w <= 160 and y+h <= 120) for x,y,w,h in boxes):
            raise ValueError('box')
        result.update(status=u32(8), seg_cycles=u32(12), count=count, boxes=boxes)
    elif magic == b'ACR2':
        index, box = u32(8), tuple(data[12:16])
        cls, ascii_code = data[936], data[937]
        x,y,w,h = box
        if index >= 64 or cls >= 36 or ascii_code != (48+cls if cls < 10 else 65+cls-10) or any(data[938:940]):
            raise ValueError('character fields')
        if not (w and h and x+w <= 160 and y+h <= 120):
            raise ValueError('character box')
        scores = struct.unpack_from('<36i', data, 788)
        if max(range(36), key=lambda i: scores[i]) != cls:
            raise ValueError('signed argmax')
        result.update(char_index=index, box=box, norm=data[16:784], norm_cycles=u32(784), scores=list(scores), core_cycles=u32(932), class_id=cls, ascii=ascii_code)
    else:
        count, status = u32(12), u32(8)
        if count > 64 or status > 255 or any(data[32+count:96]):
            raise ValueError('result fields')
        text_bytes = data[32:32+count]
        if any(not (48 <= c <= 57 or 65 <= c <= 90) for c in text_bytes):
            raise ValueError('result text')
        result.update(status=status, completed_chars=count, elapsed_cycles=u32(16), bad_captures=u32(20), skipped_frames=u32(24), publisher_dropped=u32(28), text=text_bytes)
    return result

class StreamParser:
    def __init__(self):
        self.buffer = bytearray()
        self.valid_packets = 0
        self.rejected_candidates = 0
        self.stats = {'valid_packets': 0, 'rejected_candidates': 0, 'discarded_bytes': 0, 'truncated_bytes': 0}

    def finish(self):
        self.stats['truncated_bytes'] += len(self.buffer)
        self.buffer.clear()
        return []

    def feed(self, data):
        self.buffer.extend(data)
        found = []
        while True:
            earliest = None
            accepted = False
            # 后面的完整合法包可以越过前面的截断大包，避免一直等待旧包长度。
            for offset in range(max(0, len(self.buffer)-3)):
                magic = bytes(self.buffer[offset:offset+4])
                length = LENGTHS.get(magic)
                if length is None:
                    continue
                if len(self.buffer)-offset < length:
                    if earliest is None:
                        earliest = offset
                    continue
                try:
                    item = decode_packet(bytes(self.buffer[offset:offset+length]))
                except ValueError:
                    self.rejected_candidates += 1
                    self.stats['rejected_candidates'] += 1
                    continue
                found.append(item)
                self.valid_packets += 1
                self.stats['valid_packets'] += 1
                self.stats['discarded_bytes'] += offset
                del self.buffer[:offset+length]
                accepted = True
                break
            if accepted:
                continue
            keep = earliest if earliest is not None else max(0, len(self.buffer)-3)
            if keep:
                self.stats['discarded_bytes'] += keep
                del self.buffer[:keep]
            break
        return found
