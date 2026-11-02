import unittest, struct, zlib
import norm_protocol as p
from test_norm_protocol import Stream

def response(seq=23, status=0, cycles=123, boxes=(), count=None, padding=None):
    payload=b''.join(bytes(b) for b in boxes)
    payload+=bytes(256-len(payload)) if padding is None else padding
    body=b'NSR1'+struct.pack('<IIII',seq,status,cycles,len(boxes) if count is None else count)+payload
    return body+struct.pack('<I',zlib.crc32(body))

class SegmentProtocolTests(unittest.TestCase):
    def test_segment_wire_contract(self):
        self.assertTrue(callable(getattr(p,'pack_segment',None)), 'NSG1 packer missing')
        body=b'NSG1'+struct.pack('<II',23,7)+bytes((2,3,158,119,3))
        request=p.pack_segment(23,7,(2,3,158,119),3)
        self.assertEqual(request,body+struct.pack('<I',zlib.crc32(body)))
        self.assertEqual(len(request),21)
        stream=Stream(b'noise'+response(boxes=[(12,20,7,18),(31,22,8,19)]))
        result=p.segment(stream,23,7,(2,3,158,119),3)
        self.assertEqual(stream.sent,request)
        self.assertEqual(result.boxes,[(12,20,7,18),(31,22,8,19)])
        self.assertEqual(result.cycles,123)
    def test_empty_and_64(self):
        self.assertTrue(callable(getattr(p,'unpack_segment_result',None)), 'NSR1 decoder missing')
        self.assertEqual(p.unpack_segment_result(response(),23).boxes,[])
        boxes=[(i,10,3,20) for i in range(64)]
        self.assertEqual(p.unpack_segment_result(response(boxes=boxes),23).boxes,boxes)
    def test_bad_requests(self):
        self.assertTrue(callable(getattr(p,'pack_segment',None)), 'NSG1 packer missing')
        for seq,fid,roi,flags in [(-1,2,(0,0,160,120),0),(1,2,(0,0,160),0),(1,2,(0,0,256,120),0),(1,2,(0,0,160,120),4),(1,2,(0,0,160,120),1.5)]:
            with self.assertRaises(ValueError): p.pack_segment(seq,fid,roi,flags)
    def test_bad_responses(self):
        self.assertTrue(callable(getattr(p,'unpack_segment_result',None)), 'NSR1 decoder missing')
        good=response()
        for packet in [good[:-1],good[:-1]+bytes([good[-1]^1]),response(seq=24),response(count=65),response(padding=bytes(255)+b'x')]:
            with self.assertRaises(ValueError): p.unpack_segment_result(packet,23)
        for status in (1,2,3,4):
            with self.assertRaises(p.BoardError) as err: p.unpack_segment_result(response(status=status),23)
            self.assertEqual(err.exception.status,status)
    def test_transport(self):
        self.assertTrue(callable(getattr(p,'segment',None)), 'segment exchange missing')
        with self.assertRaises(TimeoutError): p.segment(Stream(response()[:40]),23,7,(0,0,160,120),timeout=.001)
        class ShortWrite(Stream):
            def write(self,b): return len(b)-1
        with self.assertRaises(IOError): p.segment(ShortWrite(response()),23,7,(0,0,160,120))
if __name__=='__main__': unittest.main()
