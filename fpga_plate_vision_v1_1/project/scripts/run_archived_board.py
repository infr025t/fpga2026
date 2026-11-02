"""五组历史场景各取10帧做板上回归；运行前选择SW13归一化串口。"""
from pathlib import Path
import json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'pc'))
from norm_ref import SCENES

results=[]
for name,folder,roi,rotation,invert,truth in SCENES:
    out=ROOT/'reports/board'/f'archive_{name}'
    cmd=[sys.executable,str(ROOT/'pc/verify_segment_board.py'),'--frames',folder,'--limit','10','--roi',*map(str,roi),
         '--rotation',str(rotation),'--truth',truth,'--out',str(out)]
    if invert:cmd.append('--invert')
    subprocess.run(cmd,cwd=ROOT,check=True)
    subprocess.run([sys.executable,str(ROOT/'pc/recheck_saved_segment.py'),str(out)],cwd=ROOT,check=True)
    results.append(json.loads((out/'summary.json').read_text()))
(ROOT/'reports/board/archive_summary.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
