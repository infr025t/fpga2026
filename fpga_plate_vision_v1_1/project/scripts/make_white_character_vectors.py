"""蓝底白字实拍回归：原图定位，flags=2 分割及归一化；真值不输入推理。"""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'pc'))
from plate_locator import locate_plate
from segment_ref import segment_frame
from norm_ref import normalize_frame
from integer_cnn import load, logits

source = ROOT / 'sim/fixtures/blue_polarity/frame_00.npy'
raw = np.load(source, allow_pickle=False)
roi = locate_plate(raw)
seg = segment_frame(raw, roi, flags=2, skip_prefix=True, split_touching=True)
assert len(seg['boxes']) == 6
patches = np.asarray([normalize_frame(raw, box, roi, 2)[0] for box in seg['boxes']])
scores = logits(patches, load(ROOT / 'model'))
letters = [ord('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'[int(i)]) for i in scores.argmax(axis=1)]
out = ROOT / 'sim/white_character_vectors'
out.mkdir(exist_ok=True)
for name, values, width in [('frame', raw.ravel(), 2), ('pixels', patches.ravel(), 2),
                             ('scores', scores.ravel(), 8), ('ascii', letters, 2),
                             ('boxes', [int.from_bytes(bytes(b), 'little') for b in seg['boxes']], 8)]:
    (out / f'{name}.hex').write_text(''.join(f'{int(v)&((1<<(width*4))-1):0{width}x}\n' for v in values))
(out / 'manifest.json').write_text(json.dumps(dict(source=source.relative_to(ROOT).as_posix(),
    raw_sha256=hashlib.sha256(raw.tobytes()).hexdigest(), flags=2, roi=roi,
    boxes=seg['boxes'], prediction=''.join(map(chr, letters))), indent=2), encoding='utf-8')
print('Generated white-character reference:', ''.join(map(chr, letters)))
