"""对同一批实拍比较过滤前后候选框，区分粘连拆分与整串识别正确。"""
from pathlib import Path
from collections import Counter
import argparse
import json
import sys
import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'pc'))
from segment_ref import segment_frame


def check(folder):
    rows = []
    for path in sorted((folder / 'frames').glob('*/result.json')):
        result = json.loads(path.read_text(encoding='utf-8'))
        raw = np.load(path.parent / 'raw.npy')
        roi, flags = result['roi'], result['flags']
        before = segment_frame(raw, roi, flags, skip_prefix=True)['boxes']
        after = segment_frame(raw, roi, flags, skip_prefix=True,split_touching=True)['boxes']
        boundary = roi[0] + (roi[2] - roi[0]) // 8
        unchanged = [b for b in before if b in after]
        hardware = [tuple(b) for b in result['hardware_boxes']]
        rows.append(dict(frame_id=result['frame_id'], roi=roi, boundary=boundary,
                         before=before, after=after, added=len(after)-len(before),
                         unchanged_box_count=len(unchanged),
                         hardware_matches=after == hardware,
                         prediction=result['hardware_prediction']))
        if len(rows) == 1:
            logical = raw[::-1, ::-1] if flags & 1 else raw
            if flags & 2:
                logical = 255-logical
            panels = []
            for title, boxes in [('BEFORE: joined characters', before), ('AFTER: valley split', after)]:
                im = cv2.cvtColor(cv2.resize(logical, (640, 480), interpolation=cv2.INTER_NEAREST), cv2.COLOR_GRAY2BGR)
                cv2.rectangle(im, (roi[0]*4, roi[1]*4), (roi[2]*4-1, roi[3]*4-1), (0, 255, 255), 1)
                cv2.line(im, (boundary*4, roi[1]*4), (boundary*4, roi[3]*4-1), (0, 0, 255), 2)
                for x, y, w, h in boxes:
                    cv2.rectangle(im, (x*4, y*4), ((x+w)*4-1, (y+h)*4-1), (0, 255, 0), 2)
                im = cv2.copyMakeBorder(im, 36, 0, 0, 0, cv2.BORDER_CONSTANT, value=(25, 25, 25))
                cv2.putText(im, title, (12, 25), cv2.FONT_HERSHEY_SIMPLEX, .65, (255, 255, 255), 1, cv2.LINE_AA)
                panels.append(im)
            cv2.imwrite(str(folder / 'split_boxes_comparison.png'), np.hstack(panels))
    if not rows:
        raise ValueError('No captured frames')
    summary = dict(frames=len(rows), added_counts=dict(Counter(r['added'] for r in rows)),
                   unchanged_box_counts=dict(Counter(r['unchanged_box_count'] for r in rows)),
                   hardware_matches=all(r['hardware_matches'] for r in rows),
                   predictions=dict(Counter(r['prediction'] for r in rows)),
                   scope='Same raw images and dynamic ROI; old versus new segmentation; not whole-number accuracy')
    (folder / 'split_box_check.json').write_text(json.dumps(dict(summary=summary, frames=rows), indent=2), encoding='utf-8')
    print(json.dumps(summary))
    return summary['hardware_matches']


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    raise SystemExit(0 if check(parser.parse_args().folder) else 1)
