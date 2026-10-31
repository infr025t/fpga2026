import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'pc'))
from protocol import encode,decode,canvas

class ProtocolTests(unittest.TestCase):
 def test_gaussian_two_views(self):
  for f in (1,):
   for v in (0,1):
    pixels=bytes(range(36));wire=encode(pixels,v,6,6,7,128,0x12345678,256)
    d=decode(wire);self.assertEqual((d.pixels,d.source_crc),(pixels,0x12345678));self.assertEqual(len(canvas(d)),256)
 def test_removed_guided_header_is_rejected(self):
  import struct,zlib
  wire=bytearray(encode(bytes(36),1,6,6,7,128,0,256))
  wire[6]=0
  wire[28:32]=struct.pack('<I',zlib.crc32(wire[:28]))
  with self.assertRaises(ValueError):decode(wire)
 def test_bad_header_body_and_incomplete_source(self):
  wire=encode(bytes(36),1,6,6,7,128,0,256)
  for at in [0,12,40]:
   b=bytearray(wire);b[at]^=1
   with self.assertRaises(ValueError):decode(b)
  for b in [wire[:-1],encode(bytes(36),1,6,6,7,128,0,255),encode(bytes(36),1,6,6,7,128,0,256,error=1)]:
   with self.assertRaises(ValueError):decode(b)

if __name__=='__main__':unittest.main()
