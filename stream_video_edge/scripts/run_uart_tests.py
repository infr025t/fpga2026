from pathlib import Path
import sys,json,zlib,argparse,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'pc'))
from model.reference import process,pattern
from protocol import encode
from vivado_tools import run_bench
ap=argparse.ArgumentParser();ap.add_argument('--tag',default='');args=ap.parse_args()
out=Path('E:/FPGA_Test_Work/edge_v03_work')/('uart'+('_'+args.tag if args.tag else ''));out.mkdir(exist_ok=False)
image=pattern(32,24,7);np.savetxt(out/'image.hex',image.ravel(),fmt='%02x')
for f in [0,1]:
 raw,edge=process(image,f,1024,96 if f==0 else 128)
 for v,pixels in enumerate([raw,edge]):
  wire=encode(pixels.tobytes(),v,f,22,14,100+f*2+v,1024,96 if f==0 else 128,zlib.crc32(image.tobytes()),image.size)
  np.savetxt(out/f'wire_{f*2+v}.hex',np.frombuffer(wire,np.uint8),fmt='%02x')
core=ROOT/'rtl/core';sources=[core/'core_latency_pkg.sv']+[p for p in sorted(core.glob('*.sv')) if p.name!='core_latency_pkg.sv']+list((ROOT/'rtl/uart').glob('*.sv'))+[ROOT/'sim/tb_edge_uart.sv']
r=run_bench(sources,'tb_edge_uart',out,timeout=180,pass_marker='PASS tb_edge_uart',plusargs=['VECTORS='+out.as_posix()]);print(json.dumps(r,indent=2));(ROOT/'reports/uart.json').write_text(json.dumps(r,indent=2)+'\n');assert r['passed'],r.get('reason')
