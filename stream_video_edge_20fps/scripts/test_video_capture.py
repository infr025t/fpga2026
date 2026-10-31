from pathlib import Path
import sys
from vivado_tools import run_bench
r=Path(__file__).resolve().parents[1];out=r/'reports'/sys.argv[1];out.mkdir(exist_ok=False)
sources=[r/'rtl/camera/vsync_low_filter.sv',r/'rtl/camera/href_stable_filter.sv']+list((r/'rtl/camera').glob('camera_fifo_video.sv'))+[r/'sim/tb_camera_video.sv']
top='tb_camera_video'
if '--slow-data' in sys.argv:
 wrapper=out/'slow_data.sv';wrapper.write_text('module tb_slow_data;tb_camera_video #(.ACCESS_NS(35)) test();endmodule\n');sources.append(wrapper);top='tb_slow_data'
if '--y-odd' in sys.argv:
 wrapper=out/'odd.sv';wrapper.write_text('module tb_odd;tb_camera_video #(.Y_BYTE(1)) test();endmodule\n');sources.append(wrapper);top='tb_odd'
if '--vga' in sys.argv:
 wrapper=out/'vga.sv';wrapper.write_text('module tb_vga_video;tb_camera_video #(.W(640),.H(480),.CAP(393216),.HEAD(32),.BYTE_NS(55),.GAP_CYCLES(1600),.BLANK_CYCLES(260000),.BEFORE(1),.AFTER(1),.PAUSE_CYCLES(5000000)) test();endmodule\n')
 sources.append(wrapper);top='tb_vga_video'
j=run_bench(sources,top,out,timeout=600,pass_marker='PASS tb_camera_video')
print(j['reason']);sys.exit(0 if j['passed'] else 1)
