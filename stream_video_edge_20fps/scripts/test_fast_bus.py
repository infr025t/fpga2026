from pathlib import Path
import sys
from vivado_tools import run_bench
r=Path(__file__).resolve().parents[1];out=r/'reports'/sys.argv[1];out.mkdir(exist_ok=False)
j=run_bench([r/'rtl/display/nt35510_bus8.sv',r/'sim/tb_fast_bus.sv'],'tb_fast_bus',out,pass_marker='PASS tb_fast_bus')
print(j['reason']);sys.exit(0 if j['passed'] else 1)
