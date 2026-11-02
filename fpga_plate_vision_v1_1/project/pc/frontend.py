"""受限字符识别参考：模型训练不读取实拍或车牌答案，推理使用整数。"""
from pathlib import Path
import cv2
import numpy as np

CLASSES='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'

def reduce_image(a,size):
 return cv2.resize(a,size,interpolation=cv2.INTER_AREA)

def edge_image(a):
 # 软件中复现3x3整数高斯及Sobel L1；此处输入是小图，不是板上VGA边缘抽样。
 k=np.array([[1,2,1],[2,4,2],[1,2,1]],np.float32)
 smooth=((cv2.filter2D(a.astype(np.float32),-1,k,borderType=cv2.BORDER_REPLICATE).astype(np.int32)+8)>>4).astype(np.uint8)
 gx=cv2.Sobel(smooth,cv2.CV_16S,1,0,ksize=3,borderType=cv2.BORDER_REPLICATE)
 gy=cv2.Sobel(smooth,cv2.CV_16S,0,1,ksize=3,borderType=cv2.BORDER_REPLICATE)
 return ((np.abs(gx.astype(np.int32))+np.abs(gy.astype(np.int32)))>=128).astype(np.uint8)*255

def binary_image(a):
 return cv2.adaptiveThreshold(a,255,cv2.ADAPTIVE_THRESH_MEAN_C,cv2.THRESH_BINARY_INV,15,12)

def segment(a):
 # 连通域仅为PC定位参考，不计作已经具备的FPGA流式定位功能。
 mask=binary_image(a)
 _,_,stats,_=cv2.connectedComponentsWithStats(mask,8)
 lo=max(5,round(a.shape[0]*.10));hi=max(8,round(a.shape[0]*.85))
 candidates=[tuple(map(int,s[:4])) for s in stats[1:] if lo<=s[3]<=hi and s[2]>=2 and s[2]<=s[3]*1.4 and s[4]>=s[3]*1.0]
 if not candidates:return []
 # 选择同一基线的一组字符，无字符数和字符串先验。
 groups=[[b for b in candidates if abs((b[1]+b[3]/2)-(a0[1]+a0[3]/2))<max(b[3],a0[3])*.45 and .5<a0[3]/b[3]<2] for a0 in candidates]
 group=max(groups,key=lambda g:sum(b[3] for b in g))
 # 过滤字符旁的很小孤立噪点。
 mh=np.median([b[3] for b in group]);group=[b for b in group if b[3]>=mh*.65]
 return sorted(group,key=lambda b:b[0])

def normalize(a,size):
 w,h=size;out=np.zeros((h,w),np.uint8)
 scale=min((w-2)/a.shape[1],(h-2)/a.shape[0]);nw=max(1,round(a.shape[1]*scale));nh=max(1,round(a.shape[0]*scale))
 small=cv2.resize(a,(nw,nh),interpolation=cv2.INTER_AREA)
 x=(w-nw)//2;y=(h-nh)//2;out[y:y+nh,x:x+nw]=small
 return out

def feature_patch(a,box,size,kind):
 x,y,w,h=box;x0=max(0,x-2);y0=max(0,y-2);x1=min(a.shape[1],x+w+2);y1=min(a.shape[0],y+h+2)
 if kind=='edge':p=edge_image(a)[y0:y1,x0:x1]
 elif kind=='binary':p=binary_image(a)[y0:y1,x0:x1]
 else:
  p=a[y0:y1,x0:x1].astype(np.int32)
  low,high=np.percentile(p,[3,85]);den=max(16,int(high-low))
  p=np.clip(((int(high)-p)*255+den//2)//den,0,255).astype(np.uint8)
  if kind=='edge_norm':p=edge_image(p)
 return normalize(p,size)

def integer_scores(x,w,b):
 return np.asarray(x,dtype=np.int32)@np.asarray(w,dtype=np.int32).T+np.asarray(b,dtype=np.int32)

def weight_bytes(features,classes,bits):
 return (features*classes*bits+7)//8

def pack_signed(w,bits):
 if bits==8:return w.astype(np.int8).tobytes()
 a=(w.ravel().astype(np.int16)&15).astype(np.uint8)
 if len(a)%2:a=np.r_[a,np.uint8(0)]
 return (a[::2]|(a[1::2]<<4)).tobytes()

def unpack_signed(data,shape,bits):
 a=np.frombuffer(data,np.uint8)
 if bits==8:return a.view(np.int8).reshape(shape)
 v=np.empty(len(a)*2,np.int8);v[::2]=a&15;v[1::2]=a>>4
 v[v>=8]-=16
 return v[:int(np.prod(shape))].reshape(shape)

def save_model(path,w,b,bits,meta):
 import json
 path=Path(path);path.mkdir(parents=True,exist_ok=True)
 (path/'weights.bin').write_bytes(pack_signed(w,bits));(path/'bias.bin').write_bytes(b.astype('<i4').tobytes())
 meta=dict(meta,bits=bits,shape=list(w.shape),classes=CLASSES,weight_bytes=weight_bytes(w.shape[1],w.shape[0],bits),bias_bytes=b.nbytes)
 (path/'model.json').write_text(json.dumps(meta,indent=2),encoding='utf-8')

def load_model(path):
 import json
 p=Path(path);m=json.loads((p/'model.json').read_text());w=unpack_signed((p/'weights.bin').read_bytes(),m['shape'],m['bits']);b=np.frombuffer((p/'bias.bin').read_bytes(),'<i4')
 return m,w,b

def predict(patches,model):
 m,w,b=model;x=np.array(patches,np.uint8).reshape(len(patches),-1)
 if m['method']=='prototype':
  # 最近类中心的平方距离可展开成一次整数点积和类偏置。
  scores=integer_scores(x,w,b)
 else:scores=integer_scores(x,w,b)
 ix=scores.argmax(1);return ''.join(CLASSES[i] for i in ix),scores
