import struct,zlib
from dataclasses import dataclass
MAGIC=b'YVPAIR1!'
BASE=struct.Struct('<8sIHHIII')
@dataclass(frozen=True)
class Frame:
 frame_id:int
 width:int
 height:int
 tick:int
 dropped:int
 pixels:bytes
 crc:int
class Parser:
 def __init__(self):
  self.buffer=bytearray();self.header_errors=0;self.payload_errors=0;self.garbage=0
 def feed(self,data):
  self.buffer.extend(data);result=[]
  while True:
   i=self.buffer.find(MAGIC)
   if i<0:
    n=max(0,len(self.buffer)-7);self.garbage+=n;del self.buffer[:n];break
   if i:self.garbage+=i;del self.buffer[:i]
   if len(self.buffer)<32:break
   magic,fid,w,h,n,tick,drop=BASE.unpack_from(self.buffer)
   hcrc=int.from_bytes(self.buffer[28:32],'little')
   if not(0<w<=160 and 0<h<=120 and n==2*w*h) or zlib.crc32(self.buffer[:28])!=hcrc:
    self.header_errors+=1;del self.buffer[0];continue
   if len(self.buffer)<n+36:break
   payload=bytes(self.buffer[32:32+n]);crc=int.from_bytes(self.buffer[32+n:36+n],'little')
   if zlib.crc32(payload)!=crc:
    self.payload_errors+=1;del self.buffer[0];continue
   del self.buffer[:36+n];result.append(Frame(fid,w,h,tick,drop,payload,crc))
  return result
