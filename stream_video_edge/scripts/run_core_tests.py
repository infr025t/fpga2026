from pathlib import Path
import argparse,json,sys,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from model.reference import process,pattern
from vivado_tools import run_bench
ap=argparse.ArgumentParser();ap.add_argument('--size',choices=['small','vga'],default='small');ap.add_argument('--tag',default='');ap.add_argument('--pattern',choices=['ramp','constant','random','step','impulse'],default='ramp');args=ap.parse_args()
w,h=(32,24) if args.size=='small' else (640,480)
base=Path('E:/FPGA_Test_Work/edge_v03_work');base.mkdir(exist_ok=True)
out=base/('core_'+args.size+('_'+args.tag if args.tag else ''));out.mkdir(exist_ok=False)
image=pattern(w,h,7)
if args.pattern=='constant':image[:]=128
elif args.pattern=='random':image=np.random.default_rng(20261029).integers(0,256,(h,w),dtype=np.uint8)
elif args.pattern=='step':image[:,:w//2]=0;image[:,w//2:]=255
elif args.pattern=='impulse':image[:]=0;image[h//2,w//2]=255
np.savetxt(out/'image.hex',image.ravel(),fmt='%02x')
for f in [1]:
 raw,edge=process(image,threshold=128)
 np.savetxt(out/'raw.hex',raw.ravel(),fmt='%02x');np.savetxt(out/f'edge_{f}.hex',edge.ravel(),fmt='%02x')
wrapper=out/'selected.sv';wrapper.write_text(f'module tb_selected;tb_edge_core #({w},{h}) test();endmodule\n')
core=ROOT/'rtl/core';sources=sorted(core.glob('*.sv'))+[ROOT/'sim/tb_edge_core.sv',wrapper]
r=run_bench(sources,'tb_selected',out,timeout=600,pass_marker='PASS tb_edge_core',plusargs=['VECTORS='+out.as_posix()]);print(json.dumps(r,indent=2))
r['pattern']=args.pattern
(ROOT/'reports'/f'rtl_{args.size}_{args.pattern}.json').write_text(json.dumps(r,indent=2)+'\n');assert r['passed'],r.get('reason')
