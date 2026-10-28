from pathlib import Path
import sys,json
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import generate_nt35510_rom as gen
from run_runtime_tests import discover,simulate
OUT=Path(__file__).resolve().parent
profile,rows=gen.load_profile();gen.export_expected(OUT/'vectors',profile,rows)
backend,binary=discover(SimpleNamespace(simulator='auto',iverilog_bin=None,vivado_bin=None))
original=(ROOT/'sim/tb_nt35510_display.sv').read_text(encoding='utf-8')
start=original.index('    render(0);')
end=original.index('    export_ppm();',start)
stimulus='''    // Keep enable asserted across successive physical frame boundaries.
    mode_to_expect=0;@(negedge clk);pattern_select=0;enable=1;
    wait(frame_done_count==4);
    @(negedge clk);enable=0;
    repeat(50)@(negedge clk);
    if(physical_frames!=4 || frames!=4 || transaction!=5 || setup_index!=0 || busy)
      $fatal(1,"continuous frames had extra/missing pixels or transaction");
    check_margins();
'''
text=original[:start]+stimulus+original[end:]
results=[]
for name,small in [('continuous',False),('single_pixel',True)]:
    bench=OUT/(name+'.sv')
    if small:
        bench.write_text(text.replace('FULL?800:48,PH=FULL?480:40,CW=FULL?632:32,CH=FULL?472:32',
                                      'FULL?800:9,PH=FULL?480:9,CW=FULL?632:1,CH=FULL?472:1'),encoding='utf-8',newline='\n')
    else:bench.write_text(text,encoding='utf-8',newline='\n')
    sources=[*sorted((ROOT/'rtl').glob('nt35510*.sv')),bench]
    result=simulate(sources,'tb_nt35510_display',OUT/name,backend,binary,60,
        ['VECTORS='+(OUT/'vectors').as_posix()],marker='PASS tb_nt35510_display')
    results.append(result)
    print(name,result['passed'],result.get('simulation_summary',result['reason']),flush=True)
(OUT/'summary.json').write_text(json.dumps(dict(results=results),indent=2)+'\n',encoding='utf-8')
sys.exit(0 if all(r['passed'] for r in results) else 1)
