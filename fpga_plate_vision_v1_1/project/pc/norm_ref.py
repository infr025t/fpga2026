"""FPGA灰度归一化整数合同。模型、分割与答案均不参与此变换。"""
from pathlib import Path
import argparse
import collections
import hashlib
import json
import time
import numpy as np

MODEL_SHA='179d6d9b9a4e2229c152770152fe6c8d71ff924af5d9da06132debd730cf4645'
ROOT=Path(__file__).resolve().parents[1]


def _gray(a):
    a=np.asarray(a)
    if a.ndim!=2 or a.dtype!=np.uint8 or not a.size:
        raise ValueError('nonempty 2D uint8 input required')
    return a


def percentile100(a,p):
    """返回100倍线性百分位，秩为(N-1)*p/100。"""
    a=np.asarray(a)
    if a.dtype!=np.uint8 or not a.size or not 0<=p<=100 or int(p)!=p:
        raise ValueError('uint8 samples and integer percentile 0..100 required')
    hist=np.bincount(a.ravel(),minlength=256)
    rank=(a.size-1)*int(p);k,f=divmod(rank,100)
    cumulative=np.cumsum(hist)
    lo=int(np.searchsorted(cumulative,k+1))
    hi=int(np.searchsorted(cumulative,min(k+1,a.size-1)+1))
    return lo*(100-f)+hi*f


def contrast(crop):
    crop=_gray(crop)
    low100=percentile100(crop,3);high100=percentile100(crop,85)
    high=high100//100;den=max(16,(high100-low100)//100)
    out=np.clip(((high-crop.astype(np.int32))*255+den//2)//den,0,255).astype(np.uint8)
    return out,dict(low100=low100,high100=high100,high=high,den=den)


def round_even(numerator,denominator):
    """非负有理数四舍六入五成双。"""
    if numerator<0 or denominator<=0:raise ValueError('nonnegative ratio required')
    q,r=divmod(numerator,denominator)
    return q+int(2*r>denominator or (2*r==denominator and q%2==1))


def fit_dimensions(width,height):
    if width<=0 or height<=0:raise ValueError('positive dimensions required')
    if 22*height<=30*width:
        return 22,max(1,round_even(height*22,width))
    return max(1,round_even(width*30,height)),30


def _weights(source,destination):
    # 两端都以目标像素数为分母，交叠长度为整数。
    left=np.maximum(np.arange(destination)[:,None]*source,np.arange(source)[None,:]*destination)
    right=np.minimum((np.arange(destination)[:,None]+1)*source,(np.arange(source)[None,:]+1)*destination)
    return np.maximum(0,right-left).astype(np.int64)


def area_resize(crop,width,height):
    """缩小、放大均使用真面积积分；最终一次half-up舍入。"""
    crop=_gray(crop)
    if width<=0 or height<=0:raise ValueError('positive output size required')
    sh,sw=crop.shape;den=sw*sh
    accum=_weights(sh,height)@crop.astype(np.int64)@_weights(sw,width).T
    return ((accum+den//2)//den).astype(np.uint8)


def normalize_crop(crop):
    """输入已裁切灰度块，返回(32x24 uint8, 参数字典)。"""
    crop=_gray(crop);h,w=crop.shape
    normalized,meta=contrast(crop);nw,nh=fit_dimensions(w,h)
    dx=(24-nw)//2;dy=(32-nh)//2
    patch=np.zeros((32,24),np.uint8)
    patch[dy:dy+nh,dx:dx+nw]=area_resize(normalized,nw,nh)
    meta.update(crop_width=w,crop_height=h,nw=nw,nh=nh,dst_x=dx,dst_y=dy,area_den=w*h)
    return patch,meta


def feature_patch_int(image,box,roi=None):
    """box=(x,y,w,h)，ROI=(x0,y0,x1,y1)，均为image全局坐标。"""
    image=_gray(image);ih,iw=image.shape
    x,y,w,h=map(int,box)
    if w<=0 or h<=0:raise ValueError('positive bbox size required')
    rx0,ry0,rx1,ry1=(0,0,iw,ih) if roi is None else map(int,roi)
    if not 0<=rx0<rx1<=iw or not 0<=ry0<ry1<=ih:raise ValueError('ROI must be inside image')
    if not rx0<=x<x+w<=rx1 or not ry0<=y<y+h<=ry1:raise ValueError('bbox must be inside ROI')
    x0=max(rx0,x-2);y0=max(ry0,y-2);x1=min(rx1,x+w+2);y1=min(ry1,y+h+2)
    if x0>=x1 or y0>=y1:raise ValueError('padded bbox does not intersect ROI')
    patch,meta=normalize_crop(image[y0:y1,x0:x1])
    meta.update(crop_xyxy=[x0,y0,x1,y1])
    return patch,meta


def normalize_frame(image,box,roi,flags=0):
    """160x120原始帧；bit0旋转180度，bit1反相；坐标属于变换后图。"""
    image=_gray(image)
    if image.shape!=(120,160) or flags not in range(4):
        raise ValueError('160x120 frame and flags 0..3 required')
    logical=image[::-1,::-1] if flags&1 else image
    if flags&2:logical=255-logical
    return feature_patch_int(logical,box,roi)


SCENES=[
 ('anp639',ROOT/'sim/fixtures/scenes/anp639',(48,18,154,78),0,False,'ANP639'),
 ('d12345',ROOT/'sim/fixtures/scenes/d12345',(25,37,156,87),180,True,'D12345'),
 ('k38817_old',ROOT/'sim/fixtures/scenes/k38817_old',(28,32,146,86),180,False,'K38817'),
 ('k38817_v2',ROOT/'sim/fixtures/scenes/k38817_v2',(48,32,146,86),180,False,'K38817'),
 ('ddn7870',ROOT/'sim/fixtures/scenes/ddn7870',(26,35,158,87),0,False,'DDN7870'),
]


def regress(limit,out):
    import cv2
    import integer_cnn as q
    from frontend import segment,feature_patch,CLASSES
    actual_sha=hashlib.sha256((ROOT/'model/model.bin').read_bytes()).hexdigest()
    if actual_sha!=MODEL_SHA:raise ValueError('frozen model hash mismatch')
    model=q.load(ROOT/'model');out=Path(out);out.mkdir(parents=True,exist_ok=True)
    summaries=[];rows=[];vectors=[];started=time.monotonic()
    for name,folder,roi,rotation,invert,truth in SCENES:
        files=sorted(Path(folder).glob('*_selected.png'))
        if limit:files=files[:limit]
        if not files:raise ValueError(f'no selected frames in {folder}')
        current=[];absdiff=[]
        for file in files:
            image=cv2.imread(str(file),0)
            if image is None or image.shape!=(120,160):raise ValueError(str(file))
            if rotation:image=cv2.rotate(image,cv2.ROTATE_180)
            if invert:image=255-image
            x0,y0,x1,y1=roi;crop=image[y0:y1,x0:x1];boxes=segment(crop)
            legacy=[feature_patch(crop,b,(24,32),'gray') for b in boxes]
            revised=[feature_patch_int(crop,b) for b in boxes]
            if boxes:
                patches=[v[0] for v in revised]
                old_scores=q.logits(np.stack(legacy),model);new_scores=q.logits(np.stack(patches),model)
                old=''.join(CLASSES[i] for i in old_scores.argmax(1));new=''.join(CLASSES[i] for i in new_scores.argmax(1))
                differences=np.abs(np.stack(legacy).astype(np.int16)-np.stack(patches).astype(np.int16));absdiff.append(differences.ravel())
            else:old=new='';differences=np.zeros(1,np.int16)
            row=dict(scene=name,source=str(file),source_sha256=hashlib.sha256(file.read_bytes()).hexdigest(),boxes=boxes,legacy=old,rational_area=new,pixel_mae=float(differences.mean()),max_pixel_error=int(differences.max()),changed_pixels=int(np.count_nonzero(differences)),parameters=[v[1] for v in revised])
            current.append(row);rows.append(row)
            if len(current)==1:
                for i,(patch,meta) in enumerate(revised):
                    bx0,by0,bx1,by1=meta['crop_xyxy'];raw=crop[by0:by1,bx0:bx1]
                    vectors.append((f'{name}_{i}',raw,patch,meta))
        diff=np.concatenate(absdiff) if absdiff else np.zeros(1)
        summary=dict(scene=name,frames=len(current),characters=sum(len(r['boxes']) for r in current),roi=roi,rotation=rotation,invert=invert,truth_for_scoring_only=truth,legacy_exact=sum(r['legacy']==truth for r in current),rational_area_exact=sum(r['rational_area']==truth for r in current),new_regressions=sum(r['legacy']==truth and r['rational_area']!=truth for r in current),new_improvements=sum(r['legacy']!=truth and r['rational_area']==truth for r in current),changed_predictions=sum(r['legacy']!=r['rational_area'] for r in current),legacy_predictions=dict(collections.Counter(r['legacy'] for r in current)),rational_predictions=dict(collections.Counter(r['rational_area'] for r in current)),pixel_mae=float(diff.mean()),max_pixel_error=int(diff.max()),changed_pixels=int(np.count_nonzero(diff)))
        summaries.append(summary);print(json.dumps(summary),flush=True)
    export_vectors(out/'vectors',vectors)
    summary=dict(model_sha256=actual_sha,scenes=summaries,elapsed_sec=time.monotonic()-started,scope='Stored selected frames; unchanged segmentation and frozen integer CNN; no hardware evidence',quality_gate_passed=all(s['new_regressions']==0 for s in summaries),frames=sum(s['frames'] for s in summaries),characters=sum(s['characters'] for s in summaries))
    (out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    (out/'frames.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    return summary


def export_frame_vectors(folder):
    import cv2
    from frontend import segment
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(10711);random=rng.integers(0,256,(120,160),dtype=np.uint8)
    cases=[
      ('flat',np.full((120,160),97,np.uint8),(41,37,11,19),(0,0,160,120),0),
      ('tiny',random,(17,19,1,1),(17,19,18,20),0),
      ('clip_origin',random,(0,0,3,7),(0,0,160,120),0),
      ('clip_far_corner',random,(157,116,3,4),(0,0,160,120),0),
      ('clip_roi',random,(31,23,12,21),(31,23,43,44),0),
      ('fullcrop',random,(0,0,160,120),(0,0,160,120),0),
      ('tie_height',random,(32,22,40,5),(0,0,160,120),0),
      ('one_row',random,(17,19,41,1),(17,19,58,20),0),
      ('one_column',random,(17,19,1,51),(17,19,18,70),0),
    ]
    for flags in range(4):cases.append((f'flags_{flags}',random,(71,32,14,24),(48,18,154,78),flags))
    for name,source,roi,rotation,invert,_ in SCENES:
        file=sorted(Path(source).glob('*_selected.png'))[0];raw=cv2.imread(str(file),0)
        logical=raw[::-1,::-1] if rotation else raw
        if invert:logical=255-logical
        x0,y0,x1,y1=roi
        boxes=segment(logical[y0:y1,x0:x1])
        # ANP第5字符包含较大的OpenCV放大差异。
        index=4 if name=='anp639' else 0
        x,y,w,h=boxes[index]
        cases.append((name,raw,(x+x0,y+y0,w,h),roi,int(bool(rotation))+2*int(invert)))
    manifest=[];lines=[]
    for name,raw,box,roi,flags in cases:
        expected,meta=normalize_frame(raw,box,roi,flags)
        (folder/f'{name}.frame.mem').write_text(''.join(f'{v:02x}\n' for v in raw.ravel()),encoding='ascii')
        (folder/f'{name}.expected.mem').write_text(''.join(f'{v:02x}\n' for v in expected.ravel()),encoding='ascii')
        lines.append(' '.join(map(str,[name,*box,*roi,flags])))
        manifest.append(dict(name=name,box=box,roi=roi,flags=flags,parameters=meta,input_sha256=hashlib.sha256(raw.tobytes()).hexdigest(),expected_sha256=hashlib.sha256(expected.tobytes()).hexdigest()))
    (folder/'manifest.txt').write_text('\n'.join(lines)+'\n',encoding='ascii')
    (folder/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (folder/'vector_count.txt').write_text(str(len(cases))+'\n',encoding='ascii')
    return manifest


def export_vectors(folder,vectors):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(710)
    synthetic=[('flat',np.full((7,9),97,np.uint8)),('single',np.array([[255]],np.uint8)),('tiny',np.array([[0,10,20,30]],np.uint8)),('tie_height_even',rng.integers(0,256,(9,44),dtype=np.uint8)),('tall',rng.integers(0,256,(60,5),dtype=np.uint8)),('downscale',rng.integers(0,256,(52,132),dtype=np.uint8))]
    vectors=list(vectors)+[(name,a,*normalize_crop(a)) for name,a in synthetic]
    manifest=[]
    for index,(name,raw,patch,meta) in enumerate(vectors):
        prefix=f'{index:03d}_{name}'
        (folder/f'{prefix}_input.hex').write_text(''.join(f'{v:02x}\n' for v in raw.ravel()),encoding='ascii')
        (folder/f'{prefix}_expected.hex').write_text(''.join(f'{v:02x}\n' for v in patch.ravel()),encoding='ascii')
        manifest.append(dict(index=index,name=name,input_file=f'{prefix}_input.hex',expected_file=f'{prefix}_expected.hex',input_bytes=raw.size,output_bytes=patch.size,input_sha256=hashlib.sha256(raw.tobytes()).hexdigest(),output_sha256=hashlib.sha256(patch.tobytes()).hexdigest(),parameters=meta))
    (folder/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--limit',type=int,default=10);parser.add_argument('--out',type=Path,default=ROOT/'reports/norm_reference');parser.add_argument('--frame-vectors',type=Path)
    args=parser.parse_args()
    if args.limit<0:parser.error('limit must be >=0 (0 means all)')
    result=regress(args.limit,args.out)
    if args.frame_vectors:export_frame_vectors(args.frame_vectors)
    print(json.dumps({k:v for k,v in result.items() if k!='scenes'}),flush=True)
