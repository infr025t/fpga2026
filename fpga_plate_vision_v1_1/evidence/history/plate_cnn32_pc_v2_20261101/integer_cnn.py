"""纯NumPy整数推理参考。向量化oracle不是所述低缓存硬件调度。"""
from pathlib import Path
import json,struct
import numpy as np

SHAPES={'c1w':(8,1,3,3),'c1b':(8,),'c2w':(16,8,3,3),'c2b':(16,),'fcw':(36,768),'fcb':(36,)}

def budget():
 # uint8两块复用区，每块最多容纳8x32x24；卷积点上累加器和分类分数另计。
 return dict(weight_bytes=28872,bias_bytes=240,shift_bytes=8,header_bytes=8,parameter_bytes=29128,feature_pingpong_bytes=12288,score_bytes=144,point_accumulators_bytes=64,scheduled_workspace_bytes=12496,macs_per_character=304128)

def conv_same(x,w,b):
 single=x.ndim==3
 if single:x=x[None]
 p=np.pad(np.asarray(x,np.int32),((0,0),(0,0),(1,1),(1,1)))
 windows=np.lib.stride_tricks.sliding_window_view(p,(3,3),axis=(2,3))
 out=np.einsum('nchwij,ocij->nohw',windows,np.asarray(w,np.int32),optimize=True)+np.asarray(b,np.int32)[None,:,None,None]
 return out[0] if single else out

def requant_relu(a,shift):
 a=np.asarray(a,np.int32)
 if shift>0:a=(a+(1<<(shift-1)))>>shift
 elif shift<0:a=a<<(-shift)
 return np.clip(a,0,255).astype(np.uint8)

def pool2(x):
 if x.ndim==3:
  c,h,w=x.shape;return x.reshape(c,h//2,2,w//2,2).max((2,4))
 n,c,h,w=x.shape;return x.reshape(n,c,h//2,2,w//2,2).max((3,5))

def logits(x,model,trace=False):
 x=np.asarray(x,np.uint8)
 if x.ndim==2:x=x[None,None]
 elif x.ndim==3:x=x[:,None]
 a1=requant_relu(conv_same(x,model['c1w'],model['c1b']),model['shifts'][0]);p1=pool2(a1)
 a2=requant_relu(conv_same(p1,model['c2w'],model['c2b']),model['shifts'][1]);p2=pool2(a2)
 out=p2.reshape(len(x),-1).astype(np.int32)@model['fcw'].astype(np.int32).T+model['fcb']
 if trace:return out,dict(a1=a1,p1=p1,a2=a2,p2=p2)
 return out

def save(path,model,meta):
 path=Path(path);path.mkdir(parents=True,exist_ok=True)
 data=b'PCNN3201'+struct.pack('<ii',*model['shifts']);layout={}
 for key,shape in SHAPES.items():
  dtype=np.int8 if key.endswith('w') else np.dtype('<i4');a=np.asarray(model[key],dtype=dtype);assert a.shape==shape
  raw=a.tobytes();layout[key]=dict(offset=len(data),bytes=len(raw),shape=list(shape),dtype=str(a.dtype));data+=raw
 assert len(data)==budget()['parameter_bytes'] and len(data)<=32768
 (path/'model.bin').write_bytes(data)
 (path/'model.json').write_text(json.dumps(dict(meta,layout=layout,budget=budget(),shifts=model['shifts']),indent=2),encoding='utf-8')

def load(path):
 p=Path(path);data=(p/'model.bin').read_bytes();assert len(data)==budget()['parameter_bytes'] and data[:8]==b'PCNN3201'
 m={'shifts':list(struct.unpack('<ii',data[8:16]))};off=16
 for key,shape in SHAPES.items():
  dtype=np.dtype('i1') if key.endswith('w') else np.dtype('<i4');n=int(np.prod(shape))*dtype.itemsize
  m[key]=np.frombuffer(data[off:off+n],dtype=dtype).reshape(shape);off+=n
 return m

def scalar_conv(x,w,b,shift):
 """按输出点顺序累加，避免整幅int32累加图。独立核对位精确行为。"""
 oc,ic,_,_=w.shape;_,h,width=x.shape;out=np.zeros((oc,h,width),np.uint8)
 for o in range(oc):
  for y in range(h):
   for z in range(width):
    v=int(b[o])
    for c in range(ic):
     for dy in range(3):
      for dx in range(3):
       iy=y+dy-1;ix=z+dx-1
       if 0<=iy<h and 0<=ix<width:v+=int(x[c,iy,ix])*int(w[o,c,dy,dx])
    if shift>0:v=(v+(1<<(shift-1)))>>shift
    elif shift<0:v<<=-shift
    out[o,y,z]=max(0,min(255,v))
 return out

def scalar_logits(x,m):
 # 仅参考验证；FPGA预想按同样逐点调度复用硬件乘加器。
 a1=scalar_conv(x[None],m['c1w'],m['c1b'],m['shifts'][0]);p1=pool2(a1)
 a2=scalar_conv(p1,m['c2w'],m['c2b'],m['shifts'][1]);p2=pool2(a2).ravel()
 return np.array([sum(int(v)*int(w) for v,w in zip(p2,row))+int(b) for row,b in zip(m['fcw'],m['fcb'])],np.int32)
