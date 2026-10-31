import sys,tempfile,unittest,importlib.util
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'pc'))
from protocol import encode

class ReceiverTests(unittest.TestCase):
 def test_internal_source_definition_matches_board_seed(self):
  from receive import reference_pixels
  from protocol import decode
  import numpy as np,zlib
  sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
  from model.reference import process
  yy,xx=np.indices((480,640));a=(((xx+3*yy+7)^(xx>>3))&255).astype(np.uint8)
  raw,edge=process(a,threshold=128)
  f=decode(encode(edge.tobytes(),1,630,470,1,128,zlib.crc32(a.tobytes()),a.size))
  expected,crc=reference_pixels(f)
  self.assertEqual(expected,edge.tobytes());self.assertEqual(crc,f.source_crc)
 def test_receiver_exists_and_saves_without_altering_pixels(self):
  self.assertIsNotNone(importlib.util.find_spec('receive'),'EVG2 receiver is missing')
  from receive import save_frame,read_packet
  from PIL import Image
  class Port:
   def __init__(self,data):self.data=data
   def read(self,n):v=self.data[:7];self.data=self.data[7:];return v
  pixels=bytes([i%256 for i in range(630*470)])
  wire=encode(pixels,1,630,470,1,128,0x1234,640*480)
  self.assertEqual(read_packet(Port(b'noise'+wire),bytearray(),lambda:None),wire)
  with tempfile.TemporaryDirectory() as t:
   path,meta=save_frame(Path(t),1,wire,'INTERNAL',False)
   self.assertEqual(path.with_suffix('.bin').read_bytes(),pixels)
   self.assertEqual(path.with_suffix('.wire').read_bytes(),wire)
   with Image.open(path) as image:self.assertEqual(image.tobytes(),pixels)
   with Image.open(path.with_name(path.stem+'_canvas.png')) as image:
    self.assertEqual(image.size,(640,480));self.assertEqual(image.crop((5,5,635,475)).tobytes(),pixels)
   self.assertEqual(meta['source_crc32'],'00001234')

if __name__=='__main__':unittest.main()
