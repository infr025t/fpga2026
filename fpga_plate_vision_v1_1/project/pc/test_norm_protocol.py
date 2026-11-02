import unittest, struct, zlib
import numpy as np
import norm_protocol as p
class Stream:
    def __init__(self,response): self.response=response; self.sent=bytearray()
    @property
    def in_waiting(self): return min(7,len(self.response))
    def write(self,b): self.sent.extend(b); return len(b)
    def read(self,n): b=self.response[:n]; self.response=self.response[n:]; return b
class ProtocolTests(unittest.TestCase):
    def test_frame(self):
        a=np.arange(19200,dtype=np.uint8).reshape(120,160)
        b=p.pack_frame(9,a); self.assertEqual(len(b),19212)
        self.assertEqual(b[:8],b'NFR1'+struct.pack('<I',9))
        self.assertEqual(zlib.crc32(b[:-4]),struct.unpack('<I',b[-4:])[0])
        ack=b'NFA1'+struct.pack('<II',9,0); ack+=struct.pack('<I',zlib.crc32(ack))
        s=Stream(b'noise'+ack); self.assertEqual(p.upload_frame(s,9,a),9)
        self.assertEqual(bytes(s.sent),b)
    def test_character(self):
        d=(3,4,10,20,0,0,160,120,3)
        self.assertEqual(len(p.pack_character(8,9,d)),25)
        pixels=np.arange(768,dtype=np.uint8).tobytes(); scores=struct.pack('<36i',*range(-18,18))
        b=b'NRS1'+struct.pack('<IIII',8,0,101,202)+pixels+scores; b+=struct.pack('<I',zlib.crc32(b))
        self.assertEqual(len(b),936)
        r=p.recognize(Stream(b),8,9,d)
        self.assertEqual(r.norm_cycles,101); self.assertEqual(r.cnn_cycles,202)
        self.assertEqual(r.pixels.shape,(32,24)); self.assertEqual(int(r.scores[-1]),17)
        with self.assertRaises(ValueError): p.unpack_result(b,7)
        with self.assertRaises(ValueError): p.unpack_result(b[:-1]+bytes([b[-1]^1]),8)
    def test_status(self):
        b=b'NRS1'+struct.pack('<IIII',1,2,0,0)+bytes(912); b+=struct.pack('<I',zlib.crc32(b))
        with self.assertRaises(p.BoardError) as c: p.unpack_result(b,1)
        self.assertEqual(c.exception.status,2)
    def test_transport_failures(self):
        frame=np.zeros((120,160),dtype=np.uint8)
        ack=b'NFA1'+struct.pack('<II',9,0); ack+=struct.pack('<I',zlib.crc32(ack))
        with self.assertRaises(ValueError): p.upload_frame(Stream(ack),8,frame)
        with self.assertRaises(ValueError): p.upload_frame(Stream(ack[:-1]+bytes([ack[-1]^1])),9,frame)
        with self.assertRaises(TimeoutError): p.upload_frame(Stream(ack[:9]),9,frame,timeout=0.001)
        class ShortWrite(Stream):
            def write(self,b): return len(b)-1
        with self.assertRaises(IOError): p.upload_frame(ShortWrite(ack),9,frame)
        with self.assertRaises(ValueError): p.unpack_ack(ack+b'x',9)
        with self.assertRaises(ValueError): p.pack_frame(-1,frame)
        with self.assertRaises(ValueError): p.pack_character(1,2,(0,0,1,1,0,0,160,120,1.5))
    def test_validation(self):
        with self.assertRaises(ValueError): p.pack_frame(1,np.zeros((120,160),dtype=np.int32))
        with self.assertRaises(ValueError): p.pack_character(1,2,(0,0,1,1,0,0,160,120,4))
if __name__=='__main__': unittest.main()
