"""Bit-exact one-pass preprocessing and Sobel; no detail reinjection."""
import numpy as np

def image8(image):
 a=np.asarray(image)
 if a.ndim!=2 or not np.issubdtype(a.dtype,np.integer) or a.size==0 or a.min()<0 or a.max()>255:
  raise ValueError('image must be a nonempty 2D integer grayscale array in0..255')
 return a.astype(np.int64)

def gaussian3(image):
 a=image8(image)
 if min(a.shape)<3:raise ValueError('Gaussian input is too small')
 q=a[:-2,:-2]+2*a[:-2,1:-1]+a[:-2,2:]+2*a[1:-1,:-2]+4*a[1:-1,1:-1]+2*a[1:-1,2:]+a[2:,:-2]+2*a[2:,1:-1]+a[2:,2:]
 return ((q+8)>>4).astype(np.uint8)

def preprocess(image):
 a=image8(image)
 if min(a.shape)<16 or a.shape[0]>480 or a.shape[1]>640:raise ValueError('supported input16..640x480')
 return gaussian3(a)[3:-3,3:-3].copy()

def gradient(image):
 a=image8(image)
 if min(a.shape)<3:raise ValueError('Sobel input is too small')
 gx=a[:-2,2:]+2*a[1:-1,2:]+a[2:,2:]-a[:-2,:-2]-2*a[1:-1,:-2]-a[2:,:-2]
 gy=a[2:,:-2]+2*a[2:,1:-1]+a[2:,2:]-a[:-2,:-2]-2*a[:-2,1:-1]-a[:-2,2:]
 return (np.abs(gx)+np.abs(gy)).astype(np.uint16)

def sobel(image,threshold=160):
 if type(threshold) is not int or not 0<=threshold<=2040:raise ValueError('Sobel threshold0..2040')
 return np.where(gradient(image)>=threshold,255,0).astype(np.uint8)

def process(image,threshold=128):
 a=image8(image)
 return a[5:-5,5:-5].astype(np.uint8).copy(),sobel(preprocess(a),threshold)

def pattern(width=640,height=480,frame_id=1):
 yy,xx=np.indices((height,width),dtype=np.int64)
 return (((xx+3*yy+frame_id)^(xx>>3))&255).astype(np.uint8)
