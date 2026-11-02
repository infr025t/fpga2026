"""当前实拍图的固定 ROI 黄金向量；框和预测均由参考算法生成，不输入答案。"""
from pathlib import Path
import argparse
import hashlib
import json
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'pc'))
from segment_ref import segment_frame
from plate_locator import locate_plate
from norm_ref import normalize_frame
from integer_cnn import load, logits
from auto_protocol import LENGTHS, decode_packet

ROI = (0, 0, 160, 120)
OUT = ROOT / 'sim' / 'auto_located_vectors'


def generate():
    candidates = sorted((ROOT.parent / 'evidence/baseline/reports/osd_board_20/frames').glob('*/raw.npy'))
    if not candidates:
        raise FileNotFoundError('No saved current-scene raw.npy')
    src = candidates[-1]
    raw = np.load(src, allow_pickle=False)
    assert raw.shape == (120, 160) and raw.dtype == np.uint8
    roi = locate_plate(raw)
    assert roi is not None
    seg = segment_frame(raw, roi)
    assert seg['status'] == 0 and len(seg['boxes']) == 7, seg
    patches = np.array([normalize_frame(raw, box, roi, 0)[0] for box in seg['boxes']])
    scores = logits(patches, load(ROOT / 'model'))
    classes = np.argmax(scores, axis=1)
    ascii_codes = [ord('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'[int(i)]) for i in classes]
    OUT.mkdir(exist_ok=True)
    vectors = [('frame', raw.ravel(), 2), ('pixels', patches.ravel(), 2),
               ('scores', scores.ravel(), 8), ('ascii', ascii_codes, 2),
               ('boxes', [int.from_bytes(bytes(box), 'little') for box in seg['boxes']], 8)]
    for name, values, width in vectors:
        (OUT / f'{name}.hex').write_text(''.join(f'{int(v)&((1<<(4*width))-1):0{width}x}\n' for v in values))
    manifest = dict(source=str(src), source_file_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),
                    raw_sha256=hashlib.sha256(raw.tobytes()).hexdigest(), roi=roi, flags=0,
                    boxes=seg['boxes'], prediction=''.join(map(chr, ascii_codes)),
                    method='image-derived geometric ROI; reference segmentation, normalization and signed CNN argmax; no truth input')
    (OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    print(f'Generated current-scene vectors: boxes={len(seg["boxes"])} prediction={manifest["prediction"]} source={src}')


def check_wire(path):
    manifest = json.loads((OUT / 'manifest.json').read_text())
    readhex = lambda name: [int(value, 16) for value in (OUT / f'{name}.hex').read_text().split()]
    expected_raw = bytes(readhex('frame'))
    expected_pixels = bytes(readhex('pixels'))
    expected_scores = [value if value < 2**31 else value - 2**32 for value in readhex('scores')]
    expected_ascii = readhex('ascii')
    wire = path.read_bytes()
    groups = {}
    offset = 0
    packet_count = 0
    while offset < len(wire):
        magic = wire[offset:offset+4]
        assert magic in LENGTHS, (offset, magic)
        packet = decode_packet(wire[offset:offset+LENGTHS[magic]])
        groups.setdefault(packet['frame_id'], []).append(packet)
        offset += LENGTHS[magic]
        packet_count += 1
    assert offset == len(wire) and len(groups) == 2
    summaries = []
    for frame_number, (frame_id, packets) in enumerate(groups.items()):
        expected_count = 7 if frame_number == 0 else 0
        assert [p['type'] for p in packets] == ['AIF1', 'ASG2'] + ['ACR2'] * expected_count + ['AER1']
        aif, asg, aer = packets[0], packets[1], packets[-1]
        assert aif['roi'] == ROI and aif['flags'] == 0
        assert aif['raw'] == (expected_raw if frame_number == 0 else bytes([97]) * 19200)
        assert asg['roi'] == (tuple(manifest['roi']) if frame_number == 0 else (0,0,0,0))
        assert asg['status'] == 0 and asg['count'] == expected_count
        assert asg['boxes'] == ([tuple(b) for b in manifest['boxes']] if frame_number == 0 else [])
        for index, char in enumerate(packets[2:-1]):
            assert char['char_index'] == index and char['box'] == tuple(manifest['boxes'][index])
            assert char['norm'] == expected_pixels[index*768:(index+1)*768]
            assert char['scores'] == expected_scores[index*36:(index+1)*36]
            assert char['ascii'] == expected_ascii[index]
            assert char['norm_cycles'] > 0 and char['core_cycles'] > 0
        assert aer['status'] == 0 and aer['completed_chars'] == expected_count
        assert aer['text'] == (bytes(expected_ascii) if frame_number == 0 else b'')
        assert aer['bad_captures'] == 0 and aer['publisher_dropped'] == 0
        summaries.append(dict(frame_id=frame_id, text=aer['text'].decode(), characters=expected_count,
                              elapsed_cycles=aer['elapsed_cycles'], skipped_frames=aer['skipped_frames']))
    result = dict(passed=True, bytes=len(wire), packets=packet_count, frames=summaries,
                  normalized_pixels=5376, signed_scores=252, roi=ROI,
                  source_raw_sha256=manifest['raw_sha256'])
    path.with_name('wire_verification.json').write_text(json.dumps(result, indent=2))
    print(f'PASS current_scene_uart packets={packet_count} bytes={len(wire)} chars=7 pixels=5376 scores=252 CRC/raw/boxes/ASCII exact')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-wire', type=Path)
    args = parser.parse_args()
    if args.check_wire:
        check_wire(args.check_wire)
    else:
        generate()
