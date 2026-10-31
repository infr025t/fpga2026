from pathlib import Path
import sys,json,numpy as np
r=Path(__file__).resolve().parents[1];sys.path.insert(0,str(r));sys.path.insert(0,str(r/'scripts'))
from model.reference import process
from vivado_tools import run_bench
top=sys.argv[2] if len(sys.argv)>2 else 'tb_video_path'
label=sys.argv[1];out=Path('E:/FPGA_Test_Work/lcd_v04_validation')/label;out.mkdir(parents=True,exist_ok=False)
vga='--vga' in sys.argv
w,h=(640,480) if vga else (32,24)
a=np.random.default_rng(20261030).integers(0,256,(h,w),dtype=np.uint8)
np.savetxt(out/'image.hex',a.ravel(),fmt='%02x')
for f in (1,):
 raw,edge=process(a,threshold=128);np.savetxt(out/f'edge_{f}.hex',edge.ravel(),fmt='%02x')
sources=sorted((r/'rtl/core').glob('*.sv'))+[r/'rtl/runtime/video_core_adapter.sv']+[r/'sim'/f'{top}.sv']
if top=='tb_display_path':sources += [r/'rtl/runtime/video_lcd_sink.sv',r/'rtl/debug/video_snapshot.sv',r/'rtl/display/nt35510_bus8.sv',r/'rtl/display/nt35510_window_writer.sv']
if top=='tb_lcd_admission':
 sources += list((r/'rtl/camera').glob('*.sv'))+[r/'rtl/runtime/video_lcd_sink.sv',r/'rtl/runtime/capture_fault_latch.sv',r/'rtl/lcd_top.sv',r/'sim/nt35510_init_fast.sv']
 sources += [r/'rtl/display'/n for n in ['nt35510_bus8.sv','nt35510_window_writer.sv']]
if vga:
 wrapper=out/'vga_wrapper.sv';wrapper.write_text('module tb_vga;tb_video_path #(640,480) test();endmodule\n')
 sources.append(wrapper);bench='tb_vga'
else:bench=top
j=run_bench(sources,bench,out,timeout=600,pass_marker='PASS '+top,plusargs=['VECTORS='+out.as_posix()])
print(json.dumps(j,indent=2));sys.exit(0 if j['passed'] else 1)
