"""Index packaged sources, fixtures, release files and historical evidence.

Paths are relative to the package root. Hashes describe files present now;
indexing does not rerun a historical simulation or hardware observation.
"""
from pathlib import Path
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT.parent


def entry(path):
    return dict(path=path.relative_to(PACKAGE).as_posix(),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                bytes=path.stat().st_size)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT/'reports/evidence_index.json')
    args = parser.parse_args()
    groups = {}
    for name, folders in {
        'project_sources': [ROOT/name for name in ('rtl', 'constraints', 'model', 'pc', 'pc_diag', 'scripts', 'config', 'sim')],
        'release': [PACKAGE/'release'],
        'historical_evidence': [PACKAGE/'evidence'],
        'documentation': [PACKAGE/'docs'],
    }.items():
        files = []
        for folder in folders:
            files.extend(path for path in folder.rglob('*') if path.is_file()
                         and '__pycache__' not in path.parts and path.resolve() != args.out.resolve())
        if name == 'project_sources':
            files.extend(path for path in ROOT.iterdir() if path.is_file())
        groups[name] = [entry(path) for path in sorted(set(files))]
    index = dict(schema_version=2, project='fpga_plate_vision_v1_1',
                 path_base='package root (parent of project)', groups=groups,
                 scope='Current packaged file identities only; historical evidence is not a new test result.')
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(index, indent=2), encoding='utf-8')
    print(json.dumps(dict(output=str(args.out), files_indexed={name: len(files) for name, files in groups.items()})))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
