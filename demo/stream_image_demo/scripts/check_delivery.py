"""Check release hashes and the generated source listing; --refresh updates both.

Run after editing release files. Regression working directories are intentionally
excluded; copy evidence worth retaining into evidence/ before refreshing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'SHA256.json'
LISTING = '完整代码.md'
SOURCE_DIRS = ('rtl', 'constraints', 'scripts', 'pc', 'sim')
IGNORED_DIRS = {'__pycache__', '.pytest_cache', 'regression', 'xsim.dir'}


def release_files(root):
    """Enumerate deliverables without Vivado scratch files or local test output."""
    files = []
    for folder in (*SOURCE_DIRS, 'docs', 'evidence', 'build'):
        for path in (root / folder).rglob('*'):
            relative = path.relative_to(root)
            if (not path.is_file() or path.suffix in {'.pyc', '.pyo'}
                    or any(part in IGNORED_DIRS for part in relative.parts)):
                continue
            if folder == 'build' and path.suffix not in {'.log', '.rpt', '.bit'}:
                continue
            files.append(path)
    files.extend(p for p in root.iterdir()
                 if p.is_file() and p.suffix in {'.md', '.json'} and p.name != MANIFEST)
    return sorted(files, key=lambda p: p.relative_to(root).as_posix())


def source_listing(root):
    lines = [
        '# 当前Demo完整代码', '',
        '由 `python scripts/check_delivery.py --refresh` 生成，逐文件对应当前源码。',
        '功能、运行方式与验证范围见 `README_先读我.md`；历史硬件记录见 `docs/`。', '',
    ]
    for path in release_files(root):
        relative = path.relative_to(root)
        if relative.parts[0] not in SOURCE_DIRS:
            continue
        if path.suffix not in {'.sv', '.xdc', '.tcl', '.py', '.txt'}:
            continue
        language = {'.sv': 'systemverilog', '.py': 'python', '.tcl': 'tcl',
                    '.xdc': 'tcl'}.get(path.suffix, 'text')
        lines.extend([f'## {relative.as_posix()}', '', f'```{language}',
                      path.read_text(encoding='utf-8').rstrip(), '```', ''])
    return '\n'.join(lines)


def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in release_files(root)}


def check(root):
    problems = []
    try:
        expected = json.loads((root / MANIFEST).read_text(encoding='utf-8'))
    except (OSError, ValueError) as exc:
        return [f'Cannot read {MANIFEST}: {exc}']
    actual = hashes(root)
    for name in sorted(set(expected) | set(actual)):
        if name not in actual:
            problems.append(f'Missing release file: {name}')
        elif name not in expected:
            problems.append(f'Unlisted release file: {name}')
        elif expected[name] != actual[name]:
            problems.append(f'Hash mismatch: {name}')
    listing = root / LISTING
    if not listing.is_file() or listing.read_text(encoding='utf-8') != source_listing(root):
        problems.append(f'{LISTING} is out of date')
    return problems


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true',
                        help='regenerate source listing and hashes after reviewing changes')
    args = parser.parse_args(argv)
    if args.refresh:
        (ROOT / LISTING).write_text(source_listing(ROOT), encoding='utf-8', newline='\n')
        (ROOT / MANIFEST).write_text(json.dumps(hashes(ROOT), ensure_ascii=False, indent=2)
                                     + '\n', encoding='utf-8', newline='\n')
    problems = check(ROOT)
    if problems:
        print('\n'.join(problems), file=sys.stderr)
        return 1
    print(f'PASS delivery: {len(hashes(ROOT))} file hashes and current source listing')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
