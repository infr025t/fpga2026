"""Focused independent scalar A/B comparison benches."""
import argparse,json,time
from pathlib import Path
from run_core_tests import ROOT,run_bench
from run_core_synth import digest
def main():
    p=argparse.ArgumentParser();p.add_argument('--size',choices=['16','17','vga','all'],default='all');a=p.parse_args()
    work=ROOT/'build/regression/exchange'/time.strftime('%Y%m%d-%H%M%S')
    sources=[*sorted((ROOT/'rtl').glob('*.sv')),*sorted((ROOT/'rtl/experiments').glob('*.sv')),ROOT/'sim/tb_resource_exchange.sv']
    sources.sort(key=lambda s:0 if s.name=='core_latency_pkg.sv' else 1)
    hashes={str(s.relative_to(ROOT)):digest(s) for s in sources}
    results=[]
    for size,top in [('16','tb_resource_exchange'),('17','tb_resource_exchange17'),('vga','tb_resource_exchange_vga')]:
        if a.size not in ('all',size):continue
        result=run_bench(sources,top,work/size,timeout=300,pass_marker='PASS tb_resource_exchange')
        results.append(result);print(size,result['passed'],result.get('simulation_summary',result.get('reason')),flush=True)
    summary=dict(source_hashes=hashes,results=results)
    (work/'summary.json').write_text(json.dumps(summary,indent=2));print(work/'summary.json',flush=True)
    return 0 if all(r['passed'] for r in results) else 1
if __name__=='__main__':raise SystemExit(main())
