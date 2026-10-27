"""Frozen model + zlib oracle for the runtime's complete cropped outputs.

This never runs the registered quality search or modifies published profiles.
The matrix is four source patterns x all four modes, at the released profile.
"""
import hashlib
import importlib.util
import json
from pathlib import Path
import zlib

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('runtime_reference', ROOT / 'model/reference.py')
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def generate(path, width, height, patterns=(0, 1, 2, 3)):
    patterns = tuple(patterns)
    if not patterns or len(patterns) != len(set(patterns)) or any(p not in range(4) for p in patterns):
        raise ValueError('patterns must contain unique values from 0 to 3')
    path = Path(path)
    path.mkdir(parents=True, exist_ok=False)
    matrix = []
    for pattern in patterns:
        raw_crcs, selected_crcs = [], []
        for frame, mode in enumerate(reference.MODES):
            image = reference.pattern(width, height, frame, pattern)
            threshold = 2 if mode == 'DENOISE' else 4 if mode == 'ENHANCE' else 0
            gain = 256 if mode == 'DENOISE' else 428 if mode == 'ENHANCE' else 0
            layers = reference.fixed_layers(image, 1024)
            raw = layers['raw']
            base = ((layers['base_q8'] + 128) >> 8).astype(np.uint8)
            selected = reference.filter_fixed(image, 1024, threshold, gain, mode)
            packed = (raw.astype(np.uint32) << 16) | (base.astype(np.uint32) << 8) | selected
            np.savetxt(path / f'expected_p{pattern}_f{frame}.hex', packed.ravel(), fmt='%06x')
            raw_crc, selected_crc = zlib.crc32(raw.tobytes()), zlib.crc32(selected.tobytes())
            raw_crcs.append(raw_crc)
            selected_crcs.append(selected_crc)
            matrix.append(dict(pattern=pattern, frame_id=frame, mode=mode, epsilon=1024,
                               threshold=threshold, gain=gain, pixels=selected.size,
                               raw_crc=raw_crc, selected_crc=selected_crc,
                               raw_sha256=hashlib.sha256(raw.tobytes()).hexdigest(),
                               selected_sha256=hashlib.sha256(selected.tobytes()).hexdigest()))
        for name, values in [('raw', raw_crcs), ('selected', selected_crcs)]:
            (path / f'{name}_crc_p{pattern}.hex').write_text(
                ''.join(f'{value:08x}\n' for value in values), encoding='ascii')
    report = dict(width=width, height=height, matrix=matrix,
                  checked_pixels=sum(item['pixels'] for item in matrix))
    (path / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report
