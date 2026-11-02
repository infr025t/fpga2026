"""从被动观测证据计算输入帧节拍、识别节拍与全量误差；不访问设备。"""
from pathlib import Path
from collections import Counter
import argparse,json,statistics

def summarize(root):
    paths=sorted((root/'frames').glob('*/result.json'))
    rows=[json.loads(p.read_text(encoding='utf-8')) for p in paths]
    if not rows:raise ValueError('No result frames')
    intervals=[];result_intervals=[];source_frames=0
    for a,b in zip(rows,rows[1:]):
        dt=(b['capture_tick']-a['capture_tick'])&0xffffffff
        df=b['frame_id']-a['frame_id']
        if a['epoch']!=b['epoch'] or df<=0 or not dt:continue
        intervals.append(dt);source_frames+=df
        result_intervals.append((b['capture_tick']+b['timing']['elapsed_cycles']-a['capture_tick']-a['timing']['elapsed_cycles'])&0xffffffff)
    chars=[c for r in rows for c in r['characters']]
    elapsed=[r['timing']['elapsed_cycles']/100000 for r in rows]
    seg=[r['timing']['seg_cycles']/100000 for r in rows]
    norm=[c['norm_cycles']/100000 for c in chars]
    core=[c['core_cycles']/100000 for c in chars]
    stats=lambda x:dict(min=min(x),mean=statistics.mean(x),max=max(x)) if x else None
    result=dict(frames=len(rows),passed_frames=sum(r['passed'] for r in rows),characters=len(chars),
      compared_pixels=len(chars)*768,compared_scores=len(chars)*36,
      pixel_mismatches=sum(c.get('norm_pixel_mismatches',0) for c in chars),
      score_mismatches=sum(c.get('score_mismatches',0) for c in chars),
      predictions=dict(Counter(r['hardware_prediction'] for r in rows)),
      frame_id_first=rows[0]['frame_id'],frame_id_last=rows[-1]['frame_id'],
      capture_tick_first=rows[0]['capture_tick'],capture_tick_last=rows[-1]['capture_tick'],
      input_start_fps=source_frames*1e8/sum(intervals) if intervals else None,
      observed_recognition_fps=len(result_intervals)*1e8/sum(result_intervals) if result_intervals else None,
      recognition_capture_fps=len(intervals)*1e8/sum(intervals) if intervals else None,
      capture_to_result_ms=stats(elapsed),segment_ms=stats(seg),normalize_ms=stats(norm),cnn_ms=stats(core),
      counters_first=rows[0]['hardware_counters'],counters_last=rows[-1]['hardware_counters'],
      counters_max={k:max(r['hardware_counters'][k] for r in rows) for k in rows[0]['hardware_counters']},
      scope='100 MHz FPGA timestamps; input frame starts are not an independent optical measurement of LCD refresh')
    (root/'metrics.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('directory',type=Path)
    print(json.dumps(summarize(p.parse_args().directory),indent=2))
