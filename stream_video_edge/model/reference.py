"""Bit-exact one-pass preprocessing and Sobel; no detail reinjection."""
import numpy as np
EPSILONS=(16,64,256,1024)

def image8(image):
 a=np.asarray(image)
 if a.ndim!=2 or not np.issubdtype(a.dtype,np.integer) or a.size==0 or a.min()<0 or a.max()>255:
  raise ValueError('image must be a nonempty 2D integer grayscale array in0..255')
 return a.astype(np.int64)

def sum5(a):
 s=np.pad(a.cumsum(0,dtype=np.int64).cumsum(1,dtype=np.int64),((1,0),(1,0)))
 return s[5:,5:]-s[:-5,5:]-s[5:,:-5]+s[:-5,:-5]

def guided_base(image,epsilon=64):
 a=image8(image)
 if min(a.shape)<16 or epsilon not in EPSILONS:raise ValueError('guided filter size/epsilon')
 s=sum5(a);s2=sum5(a*a);v=25*s2-s*s;den=v+625*epsilon
 aq=(4096*v+den//2)//den;mu=(256*s+12)//25;bq=((4096-aq)*mu+2048)>>12
 abar=(sum5(aq)+12)//25;bbar=(sum5(bq)+12)//25
 q8=np.clip(((abar*a[4:-4,4:-4]+8)>>4)+bbar,0,65280)
 return ((q8+128)>>8).astype(np.uint8)

def gaussian3(image):
 a=image8(image)
 if min(a.shape)<3:raise ValueError('Gaussian input is too small')
 q=a[:-2,:-2]+2*a[:-2,1:-1]+a[:-2,2:]+2*a[1:-1,:-2]+4*a[1:-1,1:-1]+2*a[1:-1,2:]+a[2:,:-2]+2*a[2:,1:-1]+a[2:,2:]
 return ((q+8)>>4).astype(np.uint8)

def preprocess(image,filter_id,epsilon=64):
 a=image8(image)
 if min(a.shape)<16 or a.shape[0]>480 or a.shape[1]>640:raise ValueError('supported input16..640x480')
 if filter_id==0:return guided_base(a,epsilon)
 if filter_id==1:return gaussian3(a)[3:-3,3:-3].copy()
 raise ValueError('filter_id must be0(guided) or1(gaussian)')

def gradient(image):
 a=image8(image)
 if min(a.shape)<3:raise ValueError('Sobel input is too small')
 gx=a[:-2,2:]+2*a[1:-1,2:]+a[2:,2:]-a[:-2,:-2]-2*a[1:-1,:-2]-a[2:,:-2]
 gy=a[2:,:-2]+2*a[2:,1:-1]+a[2:,2:]-a[:-2,:-2]-2*a[:-2,1:-1]-a[:-2,2:]
 return (np.abs(gx)+np.abs(gy)).astype(np.uint16)

def sobel(image,threshold=160):
 if type(threshold) is not int or not 0<=threshold<=2040:raise ValueError('Sobel threshold0..2040')
 return np.where(gradient(image)>=threshold,255,0).astype(np.uint8)

def process(image,filter_id=0,epsilon=64,threshold=160):
 a=image8(image)
 return a[5:-5,5:-5].astype(np.uint8).copy(),sobel(preprocess(a,filter_id,epsilon),threshold)

def pattern(width=640,height=480,frame_id=1):
 yy,xx=np.indices((height,width),dtype=np.int64)
 return (((xx+3*yy+frame_id)^(xx>>3))&255).astype(np.uint8)
