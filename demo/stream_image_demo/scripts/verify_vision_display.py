"""Check standalone display pixels against the independent enhancement model."""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'pc'))
from enhancement_reference import enhance


def verify(path):
    rows = path.read_text(encoding='ascii').splitlines()
    width, height, scale = map(int, rows[0].split())
    groups = {}
    for line in rows[1:]:
        frame, processed, x, y, pixel = map(int, line.split())
        groups.setdefault((frame, processed), []).append((x, y, pixel))
    checked = 0
    for (frame, processed), pixels in groups.items():
        # Camera case frame 6 is driven through physical SCCB/FIFO pins.
        source = [[((x * 19 + y * 23 + frame * 11) % 256) if frame == 6
                   else ((180 + (x + y + frame) % 16) if x >= width // 2
                         else (40 + (x * 7 + y * 3 + frame) % 32))
                   for x in range(width)] for y in range(height)]
        output = enhance(source, 24, 16, 32)
        expected = [(x + 2, y + 2, output[y][x][3 if processed else 0])
                    for y in range(0, height - 4, scale)
                    for x in range(0, width - 4, scale)]
        if pixels != expected:
            raise ValueError(f'{path}: frame {frame} display mismatch: {pixels} != {expected}')
        checked += len(pixels)
    expected_ids = [1, 2, 4, 6] if path.name == 'vision_camera.txt' else [1, 2, 3]
    if [f for f, _ in groups] != expected_ids:
        raise ValueError(f'{path}: missing/extra display frame')
    return dict(input=path.name, width=width, height=height, scale=scale,
                frames=expected_ids, checked_pixels=checked, status='passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', nargs='+', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    reports = [verify(p) for p in args.input]
    args.out.write_text(json.dumps(reports, indent=2) + '\n', encoding='utf-8')
    print(f'PASS standalone display golden model: {sum(r["checked_pixels"] for r in reports)} pixels')


if __name__ == '__main__':
    main()
