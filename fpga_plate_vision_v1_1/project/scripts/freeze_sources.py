"""构建只读取冻结副本，防止工具运行期间编辑源码导致BIT与源码版本混淆。"""
from pathlib import Path
import hashlib,json,shutil,sys
ROOT=Path(__file__).resolve().parents[1]
dest=Path(sys.argv[1]).resolve()
if dest.exists():raise SystemExit('Frozen source directory exists; choose a new build output directory')
files=[]
for folder,glob in [('constraints','*.xdc'),('model','*.hex'),('model','*.bin'),('model','*.json')]:
    files.extend((ROOT/folder).rglob(glob))
files.extend(ROOT/p for p in (ROOT/'config/rtl_sources.txt').read_text(encoding='utf-8').splitlines() if p and not p.startswith('#'))
files.extend([ROOT/'scripts/build.tcl',ROOT/'scripts/refine_timing.tcl',ROOT/'config/rtl_sources.txt',ROOT/'config/toolchain.ps1',ROOT/'config/toolchain.tcl',ROOT/'scripts/freeze_sources.py',ROOT/'build.ps1'])
manifest={}
for source in files:
    relative=source.relative_to(ROOT);target=dest/relative;target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target);manifest[relative.as_posix()]=hashlib.sha256(target.read_bytes()).hexdigest()
(dest/'manifest.json').write_text(json.dumps(manifest,indent=2))
print(f'FROZEN {len(files)} files to {dest}')
