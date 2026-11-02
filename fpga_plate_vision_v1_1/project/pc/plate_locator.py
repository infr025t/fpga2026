"""受限场景定位：单块近水平亮底暗字牌面；只使用图像几何，不读取类别或答案。"""
import numpy as np

def locate_plate(raw):
    a=np.asarray(raw)
    if a.shape!=(120,160) or a.dtype!=np.uint8:raise ValueError('160x120 uint8 required')
    lo,hi=int(a.min()),int(a.max())
    if hi-lo<32:return None
    bright=a>((lo+hi)//2)
    counts=bright.sum(axis=1)
    best_score=0;best=None;start=None
    for end in range(121):
        valid=end<120 and counts[end]>=40
        if valid and start is None:start=end
        if not valid and start is not None:
            h=end-start
            if 0<start and end<120 and 12<=h<=60:
                row=start+int(np.argmax(counts[start:end]))
                xs=np.flatnonzero(bright[row])
                runs=np.split(xs,np.flatnonzero(np.diff(xs)>3)+1)
                # 最长白色跨度，允许中间两个暗点；并列选择较左段。
                run=max(runs,key=lambda v:int(v[-1])-int(v[0])+1)
                left,right=int(run[0]),int(run[-1])+1;w=right-left
                score=int(counts[start:end].sum())
                if left>0 and right<160 and w>=64 and w>=2*h and score>best_score:
                    best_score=score;best=(left,max(0,start-3),right-1,end-1)
            start=None
    return best
