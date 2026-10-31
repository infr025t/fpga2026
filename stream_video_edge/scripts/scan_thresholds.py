"""Same-input offline comparison; does not modify runtime or auto-tune a camera."""
from pathlib import Path
import argparse,json,sys
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from model.reference import process,preprocess,gradient

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('image',type=Path)
 ap.add_argument('--output',type=Path,required=True);ap.add_argument('--thresholds',type=int,nargs='+',default=[32,48,64,96,128,160])
 args=ap.parse_args()
 if any(t<0 or t>2040 for t in args.thresholds):ap.error('thresholds must be0..2040')
 if args.output.exists():ap.error('output must not exist; retain previous evidence')
 if args.image.suffix.lower()=='.bin':
  data=args.image.read_bytes()
  if len(data)!=640*480:ap.error('BIN must contain exactly640x480 original Y bytes; cropped UART output is not full input')
  a=np.frombuffer(data,np.uint8).reshape(480,640)
 else:
  with Image.open(args.image) as im:
   if im.mode!='L':ap.error('use an original 8-bit grayscale image')
   a=np.asarray(im).copy()
 if min(a.shape)<16 or a.shape[0]>480 or a.shape[1]>640:ap.error('input dimensions16..640x480')
 args.output.mkdir(parents=True);report=[]
 for f,name in [(1,'GAUSSIAN')]:
  base=preprocess(a);Image.fromarray(base).save(args.output/f'{name}_smoothed.png')
  for t in args.thresholds:
   raw,edge=process(a,threshold=t);Image.fromarray(edge).save(args.output/f'{name}_T{t:04d}.png')
   report.append(dict(filter=name,threshold=t,white_ratio=float((edge!=0).mean())))
 Image.fromarray(a).save(args.output/'input_raw.png')
 (args.output/'report.json').write_text(json.dumps({'input':str(args.image),'input_shape':list(a.shape),'same_input':True,'results':report,'warning':'edge density alone is not accuracy; assess missing contours and noise separately'},indent=2)+'\n')
 print(args.output)

if __name__=='__main__':main()
