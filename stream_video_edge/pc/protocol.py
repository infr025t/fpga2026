"""Gaussian-only EVG2 (algorithm byte1, legacy reserved field64); no PC image filtering. Separate framing CRC from image provenance."""
from dataclasses import dataclass
import struct,zlib
HEADER=struct.Struct('<4sBBBBHHIIHHHHI')
FOOTER=struct.Struct('<IIIII')
FILTERS={1:'GAUSSIAN'};VIEWS=('RAW','EDGE')

@dataclass(frozen=True)
class Frame:
 view:int
 filter_id:int
 width:int
 height:int
 frame_id:int
 epsilon:int # Fixed64 reserved wire metadata, never a processing parameter.
 threshold:int
 crop:int
 pixels:bytes
 payload_crc:int
 source_crc:int

def encode(pixels,view,width,height,frame_id,threshold,source_crc,input_count,error=0):
 h=struct.pack('<4sBBBBHHIIHHHH',b'EVG2',2,view,1,32,width,height,frame_id,len(pixels),64,threshold,5,0)
 return h+struct.pack('<I',zlib.crc32(h))+pixels+FOOTER.pack(zlib.crc32(pixels),source_crc,input_count,len(pixels),error)

def decode(wire):
 if len(wire)<52:raise ValueError('truncated frame')
 magic,version,view,filt,hlen,w,h,fid,n,eps,t,crop,flags,hcrc=HEADER.unpack_from(wire)
 if (magic,version,hlen,crop,flags)!=(b'EVG2',2,32,5,0) or view>1 or filt!=1 or not(6<=w<=630 and 6<=h<=470) or n!=w*h or eps!=64 or t>2040:raise ValueError('illegal header')
 if zlib.crc32(wire[:28])!=hcrc:raise ValueError('header CRC')
 if len(wire)!=32+n+20:raise ValueError('frame length')
 pixels=bytes(wire[32:32+n]);crc,source_crc,inputs,outputs,error=FOOTER.unpack_from(wire,32+n)
 if crc!=zlib.crc32(pixels):raise ValueError('pixel CRC')
 if inputs!=(w+10)*(h+10) or outputs!=n or error:raise ValueError('incomplete/failed FPGA frame')
 return Frame(view,filt,w,h,fid,eps,t,crop,pixels,crc,source_crc)

def canvas(frame):
 w,h=frame.width+10,frame.height+10;a=bytearray(w*h)
 for y in range(frame.height):a[(y+5)*w+5:(y+5)*w+5+frame.width]=frame.pixels[y*frame.width:(y+1)*frame.width]
 return bytes(a)
