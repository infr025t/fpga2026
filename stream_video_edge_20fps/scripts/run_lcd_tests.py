from pathlib import Path
import argparse,sys,json,numpy as np
r=Path(__file__).resolve().parents[1];sys.path.insert(0,str(r));sys.path.insert(0,str(r/'scripts'))
from model.reference import process
from vivado_tools import run_bench
parser=argparse.ArgumentParser(description='Run a named LCD simulation with real Vivado tools.')
parser.add_argument('label')
parser.add_argument('bench',nargs='?',default='tb_video_path',choices=[
 'tb_video_path','tb_display_path','tb_fast_display','tb_roi_snapshot',
 'tb_strip_snapshot','tb_overview_snapshot','tb_lcd_admission',
 'tb_camera_admission','tb_source_ownership','tb_statistics'])
parser.add_argument('--vga',action='store_true')
args=parser.parse_args()
top=args.bench;vga=args.vga
# 只有视频路径测试台支持尺寸参数；禁止悄悄替换用户指定的测试对象。
if vga and top!='tb_video_path':parser.error('--vga supports only tb_video_path')
if not args.label or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in args.label):
 parser.error('label must contain only letters, digits, underscore or hyphen')
label=args.label;out=r/'reports'/label;out.mkdir(parents=True,exist_ok=False)
w,h=(640,480) if vga else (32,24)
a=np.random.default_rng(20261030).integers(0,256,(h,w),dtype=np.uint8)
np.savetxt(out/'image.hex',a.ravel(),fmt='%02x')
for f in (1,):
 raw,edge=process(a,threshold=128);np.savetxt(out/f'edge_{f}.hex',edge.ravel(),fmt='%02x')
sources=sorted((r/'rtl/core').glob('*.sv'))+[r/'rtl/runtime/video_core_adapter.sv']+[r/'sim'/f'{top}.sv']
if top in ('tb_display_path','tb_fast_display','tb_roi_snapshot','tb_strip_snapshot','tb_overview_snapshot'):sources += [r/'rtl/runtime/video_lcd_sink.sv',r/'rtl/debug/video_snapshot.sv',r/'rtl/display/nt35510_bus8.sv',r/'rtl/display/nt35510_window_writer.sv']
if top in ('tb_lcd_admission','tb_camera_admission','tb_source_ownership','tb_statistics'):
 sources += [r/'rtl/camera'/n for n in ('camera_fifo_video.sv','href_stable_filter.sv','vsync_low_filter.sv','ov7670_config.sv')]
 sources += [r/'rtl/runtime/video_lcd_sink.sv',r/'rtl/runtime/capture_fault_latch.sv',r/'rtl/lcd_top.sv',r/'sim/nt35510_init_fast.sv']
 sources += [r/'rtl/display'/n for n in ['nt35510_bus8.sv','nt35510_window_writer.sv']]
if vga:
 wrapper=out/'vga_wrapper.sv';wrapper.write_text('module tb_vga;tb_video_path #(640,480) test();endmodule\n')
 sources.append(wrapper);bench='tb_vga'
else:bench=top
j=run_bench(sources,bench,out,timeout=600,pass_marker='PASS '+top,plusargs=['VECTORS='+out.as_posix()])
print(json.dumps(j,indent=2));sys.exit(0 if j['passed'] else 1)
