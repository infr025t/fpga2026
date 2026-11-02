"""只读校验提交包：检查冻结源码、下载文件和发布清单，运行时生成物不在清单内。"""
from pathlib import Path, PurePosixPath
import hashlib
import json

from check_engineering import check

PACKAGE = Path(__file__).resolve().parents[2]


def main():
    result = check()
    errors = list(result['errors'])
    manifest = json.loads((PACKAGE / 'checksums.json').read_text(encoding='utf-8'))
    for relative, expected in manifest['files'].items():
        # 清单只允许包内相对路径；不会因清单内容读取其他目录。
        parts = PurePosixPath(relative)
        if parts.is_absolute() or '..' in parts.parts or ':' in relative or '\\' in relative:
            errors.append('unsafe_manifest_path:' + relative)
            continue
        path = PACKAGE.joinpath(*parts.parts)
        if not path.is_file():
            errors.append('missing:' + relative)
        elif hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            errors.append('changed:' + relative)
    summary = dict(passed=not errors, release=manifest['release'],
                   files_checked=len(manifest['files']), rtl_modules=result['modules'],
                   protected_files=result['protected_files'], errors=errors)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
