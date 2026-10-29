from pathlib import Path
import sys,json,argparse
ROOT=Path(__file__).resolve().parents[1]
from vivado_tools import run_bench
from generate_nt35510_rom import load_profile,export_expected
ap=argparse.ArgumentParser();ap.add_argument('--full-screen',action='store_true');ap.add_argument('--display-only',action='store_true');ap.add_argument('--tag',default='');args=ap.parse_args()
base=Path('E:/FPGA_Test_Work/edge_v03_work')/('peripherals'+('_'+args.tag if args.tag else ''));base.mkdir(exist_ok=True)
results=[]
def run(name,sources,top,plusargs=(),timeout=240):
 out=base/name;out.mkdir(exist_ok=False)
 marker='PASS tb_nt35510_display' if top=='tb_nt35510_display_full' else 'PASS '+top
 r=run_bench(sources,top,out,timeout=timeout,pass_marker=marker,plusargs=plusargs)
 results.append(r);print(top,r['passed'],r.get('simulation_summary',r.get('reason')),flush=True)
 if not r['passed']:raise RuntimeError(str(r))
display=list((ROOT/'rtl/display').glob('*.sv'))
vectors=base/'vectors';profile,rows=load_profile();export_expected(vectors,profile,rows)
if not args.display_only:
 run('camera',list((ROOT/'rtl/camera').glob('*.sv'))+[ROOT/'sim/tb_camera_capture.sv'],'tb_camera_capture')
 run('bus',display+[ROOT/'sim/tb_nt35510_bus8.sv'],'tb_nt35510_bus8')
 run('init',display+[ROOT/'sim/tb_nt35510_init.sv'],'tb_nt35510_init',['VECTORS='+vectors.as_posix()])
 run('window',display+[ROOT/'sim/tb_nt35510_window.sv'],'tb_nt35510_window')
run('display_small',display+[ROOT/'sim/tb_nt35510_display.sv'],'tb_nt35510_display',['VECTORS='+vectors.as_posix()])
run('bringup',display+[ROOT/'sim/tb_nt35510_display.sv'],'tb_nt35510_bringup')
if args.full_screen:run('display_full',display+[ROOT/'sim/tb_nt35510_display.sv'],'tb_nt35510_display_full',['VECTORS='+vectors.as_posix()],timeout=600)
(ROOT/'reports/peripherals.json').write_text(json.dumps(results,indent=2)+'\n')
