"""固定ROI分割整数合同：真值仅由回归评分读取，不参与定位。"""
from collections import deque, Counter
from pathlib import Path
import argparse
import hashlib
import json
import time
import cv2
import numpy as np
from norm_ref import round_even, SCENES, MODEL_SHA, ROOT, normalize_frame


def mean15(a):
    """225项求和准确落在float64整数范围；舍入由整数公式确定。"""
    a=np.asarray(a)
    if a.ndim!=2 or a.dtype!=np.uint8 or not a.size:raise ValueError('nonempty uint8 image required')
    sums=cv2.boxFilter(a,cv2.CV_64F,(15,15),normalize=False,borderType=cv2.BORDER_REPLICATE).astype(np.int32)
    return (sums+112)//225


def threshold(a):
    return a.astype(np.int32)<=mean15(a)-12


def components(mask, with_points=False):
    """行优先种子、8邻域洪泛；先置visited再入队，每点只进队一次。"""
    pending=np.asarray(mask,dtype=bool).copy();height,width=pending.shape
    result=[]
    for y in range(height):
        for x in range(width):
            if not pending[y,x]:continue
            pending[y,x]=False;queue=deque([(x,y)])
            left=right=x;top=bottom=y;area=0;points=[]
            while queue:
                px,py=queue.popleft();area+=1
                if with_points:points.append((px,py))
                left=min(left,px);right=max(right,px);top=min(top,py);bottom=max(bottom,py)
                for ny in range(max(0,py-1),min(height,py+2)):
                    for nx in range(max(0,px-1),min(width,px+2)):
                        if pending[ny,nx]:
                            pending[ny,nx]=False;queue.append((nx,ny))
            stats=(left,top,right-left+1,bottom-top+1,area)
            result.append((stats,points) if with_points else stats)
    return result


def height_limits(height):
    return max(5,round_even(height,10)),max(8,round_even(85*height,100))


def candidates(stats,height):
    low,high=height_limits(height)
    return [(x,y,w,h) for x,y,w,h,area in stats if low<=h<=high and w>=2 and 5*w<=7*h and area>=h]


def select_group(boxes):
    best=[];best_score=0
    for _,y0,_,h0 in boxes:
        group=[b for b in boxes if 10*abs((2*b[1]+b[3])-(2*y0+h0))<9*max(b[3],h0) and 2*h0>b[3] and h0<2*b[3]]
        score=sum(b[3] for b in group)
        if score>best_score:best=group;best_score=score
    if not best:return []
    heights=sorted(b[3] for b in best);n=len(heights)
    median2=heights[(n-1)//2]+heights[n//2]
    return sorted([b for b in best if 40*b[3]>=13*median2],key=lambda b:b[0])


def filter_prefix_candidates(boxes,width):
    """首位为汉字的版式：候选中心落在牌面左1/8则排除，不读取CNN类别或真值。"""
    return [b for b in boxes if 2*b[0]+b[2]>=2*(width//8)]

def split_component(stats,points,height):
    """只拆宽连通域的低墨量谷；每个域最多拆一次，不使用类别或答案。"""
    x,y,w,h,area=stats
    low,high=height_limits(height)
    if not (low<=h<=high and h<=w<=2*h and area>=h):return None
    projection=np.bincount([px-x for px,py in points],minlength=w)
    cuts=[s for s in range(1,w) if w<=3*s<=2*w]
    if not cuts:return None
    cut=min(cuts,key=lambda s:int(projection[s-1]+projection[s]))
    if int(projection[cut-1]+projection[cut])>h//8:return None
    children=[]
    for side in [False,True]:
        pts=[(px,py) for px,py in points if (px>=x+cut)==side]
        if not pts:return None
        xs,ys=zip(*pts);cx,cy=min(xs),min(ys);cw,ch=max(xs)-cx+1,max(ys)-cy+1
        if not (cw>=2 and low<=ch<=high and 4*ch>=3*h and 5*cw<=4*h and len(pts)>=ch):return None
        children.append((cx,cy,cw,ch))
    return children


def segment_mask(mask,skip_prefix=False,split_touching=False):
    mask=np.asarray(mask,dtype=bool)
    boxes=[]
    if not split_touching:
        boxes=candidates(components(mask),mask.shape[0])
        if skip_prefix:boxes=filter_prefix_candidates(boxes,mask.shape[1])
    else:
        for stats,points in components(mask,with_points=True):
            parent=stats[:4]
            if skip_prefix and not filter_prefix_candidates([parent],mask.shape[1]):continue
            children=split_component(stats,points,mask.shape[0])
            if children and (not skip_prefix or len(filter_prefix_candidates(children,mask.shape[1]))==2):
                boxes.extend(children)
            else:boxes.extend(candidates([stats],mask.shape[0]))
    if len(boxes)>64:
        return dict(status=3,boxes=[],candidate_count=65)
    return dict(status=0,boxes=select_group(boxes),candidate_count=len(boxes))


def segment_frame(raw,roi,flags=0,skip_prefix=False,split_touching=False):
    """原始160×120灰度帧；输出坐标属于旋转/反相后的逻辑图。"""
    raw=np.asarray(raw)
    if raw.shape!=(120,160) or raw.dtype!=np.uint8:raise ValueError('160x120 uint8 frame required')
    if len(roi)!=4:return dict(status=1,boxes=[],candidate_count=0)
    x0,y0,x1,y1=map(int,roi)
    if flags not in range(4) or not 0<=x0<x1<=160 or not 0<=y0<y1<=120:
        return dict(status=1,boxes=[],candidate_count=0)
    logical=raw[::-1,::-1] if flags&1 else raw
    if flags&2:logical=255-logical
    result=segment_mask(threshold(logical[y0:y1,x0:x1]),skip_prefix=skip_prefix,split_touching=split_touching)
    result['boxes']=[(x+x0,y+y0,w,h) for x,y,w,h in result['boxes']]
    return result


def regress(limit,out):
    import integer_cnn as q
    from frontend import segment,CLASSES,binary_image
    actual_sha=hashlib.sha256((ROOT/'model/model.bin').read_bytes()).hexdigest()
    if actual_sha!=MODEL_SHA:raise ValueError('frozen model hash mismatch')
    model=q.load(ROOT/'model');out=Path(out);out.mkdir(parents=True,exist_ok=True)
    summaries=[];rows=[];started=time.monotonic()
    for name,folder,roi,rotation,invert,truth in SCENES:
        files=sorted(Path(folder).glob('*_selected.png'))
        if limit:files=files[:limit]
        if not files:raise ValueError(f'no selected frames in {folder}')
        current=[];flags=int(bool(rotation))+2*int(invert)
        for file in files:
            raw=cv2.imread(str(file),0);logical=raw[::-1,::-1] if flags&1 else raw
            if flags&2:logical=255-logical
            x0,y0,x1,y1=roi;crop=logical[y0:y1,x0:x1]
            old=[(x+x0,y+y0,w,h) for x,y,w,h in segment(crop)]
            new=segment_frame(raw,roi,flags)
            predictions=[]
            # 两路均采用已验证整数归一化，隔离分割变更的影响。
            for boxes in [old,new['boxes']]:
                patches=[normalize_frame(raw,b,roi,flags)[0] for b in boxes]
                predictions.append(''.join(CLASSES[i] for i in q.logits(np.stack(patches),model).argmax(1)) if patches else '')
            row=dict(scene=name,source=str(file),source_sha256=hashlib.sha256(file.read_bytes()).hexdigest(),roi=roi,flags=flags,status=new['status'],candidate_count=new['candidate_count'],legacy_boxes=old,integer_boxes=new['boxes'],boxes_equal=old==new['boxes'],mask_equal=bool(np.array_equal(binary_image(crop)>0,threshold(crop))),legacy_prediction=predictions[0],integer_prediction=predictions[1])
            current.append(row);rows.append(row)
        summary=dict(scene=name,frames=len(current),truth_for_scoring_only=truth,legacy_exact=sum(r['legacy_prediction']==truth for r in current),integer_exact=sum(r['integer_prediction']==truth for r in current),new_regressions=sum(r['legacy_prediction']==truth and r['integer_prediction']!=truth for r in current),new_improvements=sum(r['legacy_prediction']!=truth and r['integer_prediction']==truth for r in current),boxes_changed=sum(not r['boxes_equal'] for r in current),masks_changed=sum(not r['mask_equal'] for r in current),status_errors=sum(r['status']!=0 for r in current),legacy_predictions=dict(Counter(r['legacy_prediction'] for r in current)),integer_predictions=dict(Counter(r['integer_prediction'] for r in current)),characters=sum(len(r['integer_boxes']) for r in current))
        summaries.append(summary);print(json.dumps(summary),flush=True)
    summary=dict(model_sha256=actual_sha,scenes=summaries,frames=len(rows),characters=sum(s['characters'] for s in summaries),quality_gate_passed=all(s['new_regressions']==0 and s['status_errors']==0 and s['masks_changed']==0 for s in summaries),elapsed_sec=time.monotonic()-started,scope='Stored selected frames only; independent row-major BFS; fixed integer normalization and frozen CNN; no hardware evidence; ground truth used for scoring only')
    (out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    (out/'frames.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    return summary


def export_frame_vectors(folder):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    full=(0,0,160,120);cases=[]
    for value in [0,97,255]:cases.append((f'blank{value}',np.full((120,160),value,np.uint8),full,0))
    rng=np.random.default_rng(71101);random=rng.integers(0,256,(120,160),dtype=np.uint8)
    cases.extend([('tiny',random,(17,19,18,20),0),('one_row',random,(12,19,99,20),0),('one_column',random,(12,19,13,110),0),('random_full',random,full,0)])
    a=np.full((120,160),230,np.uint8);a[:15,:3]=0
    cases.append(('corner_origin',a,full,0))
    a=np.full((120,160),230,np.uint8);a[105:,157:]=0
    cases.append(('corner_far',a,full,0))
    a=np.zeros((120,160),np.uint8);a[20:60,30:70]=230;a[20:35,30:33]=0
    cases.append(('roi_local_border',a,(30,20,70,60),0))
    a=np.full((120,160),230,np.uint8)
    for i in range(16):a[20+i,20+i]=0
    cases.append(('diagonal8',a,full,0))
    a=np.full((120,160),230,np.uint8);a[23:43,31:35]=0;a[25:44,47:52]=0
    for flags in range(4):
        source=a[::-1,::-1] if flags&1 else a.copy()
        if flags&2:source=255-source
        cases.append((f'flags{flags}',source,(20,15,80,65),flags))
    for name,count in [('candidates64',64),('overflow65',65)]:
        a=np.full((120,160),230,np.uint8)
        for i in range(count):
            y=(i//9)*14;x=(i%9)*10
            a[y:y+12,x:x+2]=0
        cases.append((name,a,full,0))
    for height in [65,70]:
        a=np.full((120,160),230,np.uint8);a[20:26,20:22]=0;a[20:27,30:32]=0
        cases.append((f'height_tie{height}',a,(10,10,90,10+height),0))
    for name,source,roi,rotation,invert,_ in SCENES:
        file=sorted(Path(source).glob('*_selected.png'))[0]
        cases.append((name,cv2.imread(str(file),0),roi,int(bool(rotation))+2*int(invert)))
    cases.append(('invalid_far_roi',random,(159,119,161,120),0))
    manifest=[];lines=[]
    for name,raw,roi,flags in cases:
        result=segment_frame(raw,roi,flags)
        (folder/f'{name}.frame.mem').write_text(''.join(f'{v:02x}\n' for v in raw.ravel()),encoding='ascii')
        logical=raw[::-1,::-1] if flags&1 else raw
        if flags&2:logical=255-logical
        x0,y0,x1,y1=roi
        mask=threshold(logical[y0:y1,x0:x1]) if result['status']!=1 else np.zeros((0,0),bool)
        (folder/f'{name}.mask.mem').write_text(''.join(f'{int(v):01x}\n' for v in mask.ravel()),encoding='ascii')
        values=[name,*roi,flags,result['status'],len(result['boxes'])]
        values.extend(v for box in result['boxes'] for v in box)
        lines.append(' '.join(map(str,values)))
        manifest.append(dict(name=name,roi=roi,flags=flags,**result,input_sha256=hashlib.sha256(raw.tobytes()).hexdigest(),foreground_pixels=int(mask.sum())))
    (folder/'manifest.txt').write_text('\n'.join(lines)+'\n',encoding='ascii')
    (folder/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    (folder/'vector_count.txt').write_text(str(len(manifest))+'\n',encoding='ascii')
    # 全1 mask只用于洪泛队列压力测试；正常局部阈值不可能使全图为前景。
    (folder/'full_foreground.injected_mask.mem').write_text('1\n'*19200,encoding='ascii')
    return manifest


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--limit',type=int,default=10);parser.add_argument('--out',type=Path,default=ROOT/'reports/segmentation_reference');parser.add_argument('--frame-vectors',type=Path)
    args=parser.parse_args()
    if args.limit<0:parser.error('limit must be >=0 (0 means all)')
    result=regress(args.limit,args.out)
    if args.frame_vectors:export_frame_vectors(args.frame_vectors)
    print(json.dumps({k:v for k,v in result.items() if k!='scenes'}),flush=True)
