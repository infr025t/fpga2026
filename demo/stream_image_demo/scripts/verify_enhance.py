"""Compare every emitted RTL pixel with an independent integer image model."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'pc'))
from enhancement_reference import enhance, fixture_controls, fixture_pixel


def verify(path):
    with path.open(encoding='ascii') as handle:
        width, height, frames = map(int, handle.readline().split())
        checked = 0
        minima, maxima = 255, 0
        for frame in range(frames):
            source = [[fixture_pixel(frame, x, y, width) for x in range(width)]
                      for y in range(height)]
            expected = enhance(source, *fixture_controls(frame))
            for y, row in enumerate(expected, 2):
                for x, pixels in enumerate(row, 2):
                    line = handle.readline()
                    actual = tuple(map(int, line.split()))
                    reference = (frame, x, y, *pixels,
                                 int(x == 2 and y == 2), int(x == width - 3),
                                 int(x == width - 3 and y == height - 3))
                    if actual != reference:
                        raise ValueError(f'{path}: pixel {checked}: {actual} != {reference}')
                    minima = min(minima, pixels[-1]); maxima = max(maxima, pixels[-1])
                    checked += 1
        if handle.read().strip():
            raise ValueError(f'{path}: extra RTL output')
    return dict(input=path.name, width=width, height=height, frames=frames,
                checked_pixels=checked, minimum=minima, maximum=maxima,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest(), status='passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', nargs='+', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    reports = [verify(path) for path in args.input]
    args.out.write_text(json.dumps(reports, indent=2) + '\n', encoding='utf-8')
    print(f'PASS enhancement golden model: {sum(r["checked_pixels"] for r in reports)} pixels')


if __name__ == '__main__':
    main()
