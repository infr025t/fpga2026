"""Camera adapter regression, using only this project's sources."""
from pathlib import Path
import argparse,json,shutil
from vivado_tools import run_bench
ROOT=Path(__file__).resolve().parents[1]
ap=argparse.ArgumentParser();ap.add_argument('--tag',required=True);args=ap.parse_args()
out=Path('E:/FPGA_Test_Work/edge_v03_work')/('camera_'+args.tag);out.mkdir(exist_ok=False)
camera=list((ROOT/'rtl/camera').glob('*.sv'));results=[]
cases=[('small','tb_camera_capture',None),
 ('vga','tb_camera_capture','#(.W(640),.H(480),.CAP(393216),.HEAD_ROWS(32),.CAPTURES(1))'),
 ('short_pulse','tb_camera_capture','#(.GLITCH_TEST(1),.GLITCH_CYCLES(5))'),
 ('invalid_frame','tb_camera_capture','#(.GLITCH_TEST(1),.GLITCH_CYCLES(128),.EXPECT_ERROR(1))'),
 ('recovery','tb_camera_recovery',None),('vsync','tb_vsync_filter',None),('config','tb_camera_config',None)]
for name,bench,params in cases:
 work=out/name;work.mkdir()
 sources=camera+[ROOT/'sim'/(bench+'.sv')];top=bench
 if params:
  wrapper=work/'selected.sv';wrapper.write_text(f'module tb_selected;{bench} {params} test();endmodule\n')
  sources.append(wrapper);top='tb_selected'
 r=run_bench(sources,top,work,timeout=180,pass_marker='PASS '+bench)
 evidence=ROOT/'reports/evidence/camera'/name;evidence.mkdir(parents=True,exist_ok=True)
 for log in ('xvlog-captured.log','xelab-captured.log','xsim-captured.log','result.json'):
  if (work/log).exists():shutil.copy2(work/log,evidence/log)
 results.append(dict(case=name,**r));print(name,r['passed'],r.get('simulation_summary',r.get('reason')),flush=True)
 if not r['passed']:raise SystemExit(1)
(ROOT/'reports/camera.json').write_text(json.dumps(results,indent=2)+'\n')
print('PASS camera suite:7 cases, tagged frames, VGA, byte prefetch, short/long VSYNC, recovery and auto AEC/AGC')
