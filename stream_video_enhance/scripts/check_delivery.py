"""Verify the VGA project's release bytes; --refresh regenerates its manifest.

Build scratch and Python caches are excluded. Historical reports remain part
of the release, so changing old evidence is detectable as well as source drift.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'SHA256.json'
DIRECTORIES = ('rtl', 'sim', 'scripts', 'tests', 'model', 'docs', 'reports')


def hashes(root=ROOT):
    paths = [p for directory in DIRECTORIES for p in (root / directory).rglob('*')
             if p.is_file() and '__pycache__' not in p.parts and p.suffix not in ('.pyc', '.pyo')]
    paths += [p for p in root.iterdir() if p.is_file() and p.suffix in ('.md', '.json') and p.name != 'SHA256.json']
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true')
    args = parser.parse_args()
    try:
        current = hashes()
        if args.refresh:
            MANIFEST.write_text(json.dumps(current, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        expected = json.loads(MANIFEST.read_text(encoding='utf-8'))
        changed = [name for name in sorted(current.keys() | expected.keys())
                   if current.get(name) != expected.get(name)]
    except (OSError, ValueError, TypeError, AttributeError) as error:
        print(f'FAIL delivery: {error}', file=sys.stderr)
        return 1
    if changed:
        print('FAIL delivery:\n' + '\n'.join(changed), file=sys.stderr)
        return 1
    print(f'PASS VGA delivery: {len(current)} exact file hashes')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
