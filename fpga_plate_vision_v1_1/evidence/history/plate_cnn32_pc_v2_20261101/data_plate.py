"""完整第三方车牌字形增强，训练代码不读取实拍目录/真值。"""
from pathlib import Path
import json,hashlib
import numpy as np,cv2
from frontend import CLASSES,feature_patch
ROOT=Path(__file__).resolve().parent
OLD=Path('E:/FPGA_Test_Work/plate_cnn32_pc_20261101')
GLYPHS=ROOT/'vendor/plate_generator/font_model'

def label_of(path):
 tail=path.stem.rsplit('_',1)[-1]
 return tail if len(tail)==1 and tail in CLASSES else None

def augment(path,rng):
 ink=cv2.imread(str(path),0);ys,xs=np.where(ink<150);ink=ink[ys.min():ys.max()+1,xs.min():xs.max()+1]
 # 先模拟物理字符形状的粗细，再模拟拍摄缩小、亚像素位置、失焦和照度。
 if rng.random()<.5:
  n=int(rng.integers(1,3));kernel=np.ones((n,n),np.uint8)
  ink=cv2.erode(ink,kernel) if rng.random()<.5 else cv2.dilate(ink,kernel)
 h=int(rng.integers(13,44));w=max(2,round(ink.shape[1]/ink.shape[0]*h*rng.uniform(.75,1.3)))
 ink=cv2.resize(ink,(w,h),interpolation=cv2.INTER_AREA)
 bg=int(rng.integers(150,246));fg=int(rng.integers(0,bg-45));a=(fg+(bg-fg)*ink.astype(float)/255).astype(np.uint8)
 a=np.pad(a,((8,8),(8,8)),constant_values=bg)
 m=cv2.getRotationMatrix2D((a.shape[1]/2,a.shape[0]/2),float(rng.uniform(-9,9)),1);m[0,1]+=float(rng.uniform(-.10,.10));m[:,2]+=rng.uniform(-.5,.5,2)
 a=cv2.warpAffine(a,m,(a.shape[1],a.shape[0]),borderValue=bg)
 a=cv2.GaussianBlur(a,(3,3),float(rng.uniform(.1,.8)))
 a=np.clip(a.astype(float)+rng.normal(0,rng.uniform(.1,2.5),a.shape),0,255).astype(np.uint8)
 if bg-int(a.min())<15:return augment(path,rng)
 ys,xs=np.where(a<(bg+int(a.min()))/2);box=(int(xs.min()),int(ys.min()),int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1))
 return a,box

def generate(paths,repeats,seed):
 rng=np.random.default_rng(seed);data={'gray':[],'edge_norm':[],'labels':[]}
 for path in paths:
  label=CLASSES.index(label_of(path))
  for _ in range(repeats):
   a,b=augment(path,rng);dx=int(rng.integers(-1,2));dy=int(rng.integers(-1,2));m=np.array([[1,0,dx],[0,1,dy]],np.float32)
   for kind in ['gray','edge_norm']:
    p=feature_patch(a,b,(24,32),kind);p=cv2.warpAffine(p,m,(24,32),flags=cv2.INTER_NEAREST,borderValue=0);data[kind].append(p)
   data['labels'].append(label)
 return {k:np.array(v,np.int64 if k=='labels' else np.uint8) for k,v in data.items()}

def main():
 out=ROOT/'data';out.mkdir(exist_ok=True);manifest={}
 train_paths=sorted(p for p in GLYPHS.glob('*.jpg') if label_of(p) and not p.name.startswith('green_'))
 test_paths=sorted(p for p in GLYPHS.glob('green_*.jpg') if label_of(p))
 assert set(train_paths).isdisjoint(test_paths)
 for split,paths,repeats,seed in [('plate_train',train_paths,128,3157),('plate_validation',train_paths,20,7742),('plate_test',test_paths,40,9917)]:
  arrays=generate(paths,repeats,seed);dest=out/f'{split}.npz';np.savez_compressed(dest,**arrays)
  manifest[split]=dict(seed=seed,repeats=repeats,samples=len(arrays['labels']),source_hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},sha256=hashlib.sha256(dest.read_bytes()).hexdigest())
  print(split,len(arrays['labels']),flush=True)
 generic=np.load(OLD/'data/train.npz');plate=np.load(out/'plate_train.npz')
 np.savez_compressed(out/'train.npz',**{k:np.concatenate([generic[k],plate[k]]) for k in ['gray','edge_norm','labels']})
 # 保留原始泛化测试；验证集合并只作为方便读取，选轮时两部分分别等权。
 for split in ['validation','test']:
  original=np.load(OLD/'data'/f'{split}.npz');np.savez_compressed(out/f'{split}.npz',**{k:original[k] for k in original.files})
 manifest['generic_source_manifest']=json.loads((OLD/'data/manifest.json').read_text())
 manifest['combined_training_sha256']=hashlib.sha256((out/'train.npz').read_bytes()).hexdigest()
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2));print('DATA_READY',flush=True)
if __name__=='__main__':main()
