"""从落盘图像与板上框复核分割，再核对保存的归一化和CNN输出。"""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
import numpy as np
from segment_ref import segment_frame
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser();p.add_argument('report',type=Path);args=p.parse_args()
    rows=json.loads((args.report/'frames.json').read_text());bad=0
    if not rows:raise ValueError('Empty report')
    frame_indices=[r['frame_index'] for r in rows]
    if len(set(frame_indices))!=len(rows):raise ValueError('Duplicate frame index')
    by_frame={r['frame_index']:r for r in rows};seen=set();sequences=set()
    characters=[json.loads(line) for line in (args.report/'characters.jsonl').read_text().splitlines()]
    for char in characters:
        fi=char['frame_index'];ci=char['character_index'];key=(fi,ci)
        if fi not in by_frame or key in seen or char['sequence'] in sequences:raise ValueError('Duplicate or unknown character record')
        row=by_frame[fi]
        if not 0<=ci<len(row['fpga_boxes']):raise ValueError('Character index outside FPGA box list')
        descriptor=[*row['fpga_boxes'][ci],*row['roi'],row['flags']]
        if list(char['descriptor'])!=descriptor or char['frame_id']!=row['frame_id']:raise ValueError('Character request did not match FPGA box/frame')
        seen.add(key);sequences.add(char['sequence'])
    required={(r['frame_index'],ci) for r in rows for ci in range(len(r['fpga_boxes']))}
    if seen!=required:raise ValueError('Incomplete character coverage of FPGA boxes')
    for row in rows:
        raw=np.frombuffer((args.report/'frames_raw'/f"{row['frame_index']:04d}.bin").read_bytes(),np.uint8).reshape(120,160)
        if hashlib.sha256(raw.tobytes()).hexdigest()!=row['raw_sha256']:raise ValueError('Raw frame hash mismatch')
        result=segment_frame(raw,row['roi'],row['flags'])
        bad+=int(result['status']!=0 or result['boxes']!=[tuple(b) for b in row['fpga_boxes']])
    subprocess.run([sys.executable,str(ROOT/'pc/recheck_saved_board.py'),str(args.report)],check=True)
    result=dict(status='PASS' if bad==0 else 'FAIL',frames=len(rows),box_mismatched_frames=bad)
    (args.report/'segmentation_recheck.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result))
    if bad:raise AssertionError(result)

if __name__=='__main__':main()
