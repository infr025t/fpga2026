"""Explicit snapshot/check of the new project; never rewrites source or reports."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
MANIFEST=ROOT/'SHA256.json'
def files():
 return sorted(f for f in ROOT.rglob('*') if f.is_file() and f!=MANIFEST and not any(x in f.parts for x in ['.git','.Xil','__pycache__']) and f.suffix not in ['.pyc','.jou','.wdb','.dcp'])
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--refresh',action='store_true',help='Write reviewed file hashes; use only after verification');args=ap.parse_args()
 current={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files()}
 summary=json.loads((ROOT/'reports/summary.json').read_text())
 for key,name in [('sha256','artifacts/edge_top.bit'),('ltx_sha256','artifacts/edge_top.ltx')]:
  if current.get(name)!=summary['artifact'][key]:print('FAIL artifact/report mismatch:',name);return 1
 provenance=json.loads((ROOT/'docs/camera_source_provenance.json').read_text())
 for entry in provenance['changes']:
  if current.get(entry['project_file'])!=entry['project_sha256']:print('FAIL accepted camera source mapping:',entry['project_file']);return 1
 if args.refresh:MANIFEST.write_text(json.dumps(current,indent=2)+'\n')
 expected=json.loads(MANIFEST.read_text())
 if current!=expected:
  changed=sorted(k for k in current.keys()|expected.keys() if current.get(k)!=expected.get(k));print('FAIL file snapshot:',changed);return 1
 result=subprocess.run(['git','-C',str(ROOT.parent),'diff','--quiet','origin/main','--','demo'])
 if result.returncode:print('FAIL preserved demo differs from main baseline');return 1
 print(f'PASS V0.3 delivery: {len(current)} exact files; demo unchanged from origin/main');return 0
if __name__=='__main__':raise SystemExit(main())
