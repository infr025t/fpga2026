"""发布工程门禁：结构、驱动分层及已验收硬件源码的逐字节一致性。"""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT.parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check():
    errors, modules = [], {}
    sources = [line.strip() for line in (ROOT / 'config/rtl_sources.txt').read_text().splitlines()
               if line.strip() and not line.startswith('#')]
    for folder in ('rtl', 'pc', 'pc_diag', 'scripts', 'config', 'constraints'):
        for path in (ROOT / folder).rglob('*'):
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            if not re.fullmatch(r'[a-z0-9_]+\.[a-z0-9_]+', path.name):
                errors.append('filename:' + str(path.relative_to(ROOT)))
    for path in (ROOT / 'rtl').rglob('*.sv'):
        names = re.findall(r'^module\s+(\w+)', path.read_text(encoding='utf-8'), re.M)
        if names != [path.stem]:
            errors.append('one_module_per_file:' + str(path.relative_to(ROOT)))
        for name in names:
            if name in modules:
                errors.append('duplicate_module:' + name)
            modules[name] = path
        if path.relative_to(ROOT).as_posix() not in sources:
            errors.append('unlisted:' + str(path.relative_to(ROOT)))
    for source in sources:
        if not (ROOT / source).is_file():
            errors.append('missing_source:' + source)
    if len(sources) != len(set(sources)):
        errors.append('duplicate_sources')
    # 外设驱动不能反向依赖视频算法或识别业务，保证可单独复用。
    for name, path in modules.items():
        text = re.sub(r'//[^\n]*|/\*.*?\*/', '', path.read_text(encoding='utf-8'), flags=re.S)
        for other, target in modules.items():
            if other == name:
                continue
            if re.search(r'\b' + other + r'\s*(?:#\s*\(|\w+\s*\()', text):
                if 'drivers' in path.parts and ('recognition' in target.parts or 'video' in target.parts):
                    errors.append(f'driver_business_dependency:{name}->{other}')
    # 以发布清单所指向的实际构建为准，检查算法、外设时序、模型与引脚的源码身份。
    release = json.loads((PACKAGE / 'release/release_manifest.json').read_text(encoding='utf-8'))
    frozen = (PACKAGE / release['frozen_source_manifest']).parent
    manifest = json.loads((frozen / 'manifest.json').read_text(encoding='utf-8'))
    protected = []
    for relative, digest in manifest.items():
        if not (frozen / relative).is_file() or sha(frozen / relative) != digest:
            errors.append('frozen_evidence_changed:' + relative)
        if relative.startswith(('rtl/', 'model/', 'constraints/', 'config/')):
            if not (ROOT / relative).is_file() or sha(ROOT / relative) != digest:
                errors.append('accepted_source_changed:' + relative)
            else:
                protected.append(relative)
    for relative, digest in release['artifacts'].items():
        path = PACKAGE / relative
        if not path.is_file() or sha(path) != digest:
            errors.append('release_artifact_changed:' + relative)
    return dict(passed=not errors, errors=errors, rtl_sources=len(sources), modules=len(modules),
                frozen_files=len(manifest), protected_files=len(protected),
                protected_unchanged=protected,
                scope='Structure and accepted artifact identity; hardware behavior uses the archived implementation and board evidence')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, help='可选报告路径；默认只读检查')
    args = parser.parse_args()
    result = check()
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
