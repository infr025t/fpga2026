"""Reproducible local synthesis; no implementation or board programming."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
from run_core_tests import ROOT, BIN, _run_tool

REQUIRED_SIMULATION_SOURCES = {
    'rtl/' + name for name in (
        'core_latency_pkg.sv', 'token_pipe.sv', 'div25_pipe.sv', 'ratio_q12_pipe.sv',
        'row_window5.sv', 'moments5.sv', 'coefficient_box5.sv', 'coefficient5.sv',
        'reconstruct.sv', 'detail_enhance.sv', 'guided_core.sv')
} | {'sim/tb_core_stages.sv', 'sim/tb_guided_core.sv', 'scripts/core_vectors.py'}

REQUIRED_SIMULATION_TOPS = {
    'tb_core_stages', 'tb_guided_core_16', 'tb_guided_core_16_align',
    'tb_guided_core_17', 'tb_guided_core_17_align',
    'tb_guided_core_vga', 'tb_guided_core_vga_align',
    'tb_core_faults_0', 'tb_core_faults_1',
}


def verify_simulation_sources(manifest, root=ROOT):
    """Bind numerical simulation to RTL/oracle inputs, not the tool wrapper.

    Runner diagnostics may change without changing the simulated computation.
    Every recorded rtl/sim/model input and the numerical vector generator is
    checked. All nine complete-core regression cases must have passed. Older
    manifests without model hashes bind only their recorded numerical inputs.
    """
    if not isinstance(manifest, dict):
        raise ValueError('simulation manifest must be a JSON object')
    results = manifest.get('results')
    if not isinstance(results, list) or not results or any(
            not isinstance(result, dict) or result.get('passed') is not True
            for result in results):
        raise ValueError('simulation manifest must contain only passing results')
    recorded_tops = {result.get('top') for result in results
                     if isinstance(result.get('top'), str)}
    missing_tops = REQUIRED_SIMULATION_TOPS - recorded_tops
    if missing_tops:
        raise ValueError('simulation manifest is missing core regression cases: '
                         + ', '.join(sorted(missing_tops)))
    sources = manifest.get('source_hashes')
    if not isinstance(sources, dict):
        raise ValueError('simulation manifest is missing source_hashes')
    missing = REQUIRED_SIMULATION_SOURCES - sources.keys()
    if missing:
        raise ValueError('simulation manifest is missing core sources: ' + ', '.join(sorted(missing)))
    root = Path(root).resolve()
    checked = []
    for name, expected in sources.items():
        relative = Path(name)
        path = (root / relative).resolve()
        if relative.is_absolute() or not path.is_relative_to(root):
            raise ValueError('invalid simulation source path: ' + name)
        if (not relative.parts or relative.parts[0] not in ('rtl', 'sim', 'model')) \
                and name != 'scripts/core_vectors.py':
            continue
        if not isinstance(expected, str) or re.fullmatch('[0-9a-f]{64}', expected) is None:
            raise ValueError('invalid simulation source hash: ' + name)
        if not path.is_file():
            raise ValueError('simulation source is missing: ' + name)
        if digest(path) != expected:
            raise ValueError('simulation source changed since the recorded run: ' + name)
        checked.append(name)
    return sorted(checked)


def check_diagnostics(output, code):
    failures = []
    if code != 0: failures.append('timeout' if code is None else f'exit {code}')
    if re.search(r'(?im)^\s*(ERROR:|FATAL:|CRITICAL WARNING:)', output):
        failures.append('error or critical warning')
    if not re.search(r'(?m)^PASS SYNTH\s*$', output): failures.append('missing PASS SYNTH')
    return failures

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def check_metrics(metrics, top):
    failures=[]
    for key in ('latches','multidrivers','combinational_loops','unconstrained_internal_endpoints',
                'no_input_delay','no_output_delay','no_clock'):
        if metrics[key]: failures.append(key)
    if metrics['registered_setup_slack_ns'] < 0: failures.append('registered timing')
    if metrics['registered_hold_slack_ns'] < 0: failures.append('registered hold')
    if metrics['overall_setup_slack_ns'] < 0: failures.append('boundary timing')
    if top=='guided_core':
        for key,limit in {'DSP':24,'LUT':12000,'FF':20000}.items():
            if metrics[key]>limit: failures.append(f'{key} cap')
        if metrics['RAMB36']+metrics['RAMB18']/2>24: failures.append('BRAM cap')
    return failures

def package_latencies():
    text=(ROOT/'rtl/core_latency_pkg.sv').read_text()
    values={k:int(v) for k,v in re.findall(r'\b(L_\w+)\s*=\s*(\d+)',text)}
    values['L_CORE']=sum(values.values())
    values['EXTRA_ALIGN_1_L_CORE']=values['L_CORE']+1
    return values

def run(top, work, timeout, route=False):
    work.mkdir(parents=True, exist_ok=True)
    command = [str(BIN / 'vivado.bat'), '-mode', 'batch', '-nojournal', '-source',
               str(ROOT / 'scripts/synth_core.tcl'), '-tclargs', str(ROOT), top, str(work),
               'route' if route else 'synth']
    start = time.monotonic()
    log = work / 'captured.log'
    with log.open('w', encoding='utf-8') as stream:
        code, timed_out = _run_tool(command, work, stream, timeout)
    output = log.read_text(encoding='utf-8', errors='replace')
    failures = check_diagnostics(output, code)
    metrics = {}
    if (work / 'metrics.json').exists():
        metrics = json.loads((work / 'metrics.json').read_text())
        utilization=(work/'utilization.rpt').read_text()
        # Slice LUTs includes SRLs and Vivado's LUT combining adjustment.
        metrics['LUT']=int(re.search(r'\| Slice LUTs\*\s*\|\s*(\d+)',utilization)[1])
        timing=(work/'check_timing.rpt').read_text()
        for key in ('unconstrained_internal_endpoints','no_input_delay','no_output_delay','no_clock'):
            match=re.search(r'checking '+key+r' \((\d+)\)',timing)
            metrics[key]=int(match[1]) if match else -1
        failures.extend(check_metrics(metrics,top))
    else: failures.append('missing metrics')
    routed=None
    if route:
        if (work/'routed_metrics.json').exists():
            routed=json.loads((work/'routed_metrics.json').read_text())
            if routed['setup_slack_ns']<0: failures.append('routed setup')
            if routed['hold_slack_ns']<0: failures.append('routed hold')
        else: failures.append('missing routed metrics')
    result = dict(top=top, command=command, exit=code, timeout=timed_out,
                  seconds=round(time.monotonic()-start,3), passed=not failures,
                  failures=failures, metrics=metrics, routed=routed,
                  acceptance_scope='OOC resource/diagnostic/setup gate; synthesis hold is reported, not closure' + ('; local routed setup/hold gate' if route else ''),
                  warnings=len(re.findall(r'(?m)^WARNING:', output)),
                  critical_warnings=len(re.findall(r'(?m)^CRITICAL WARNING:',output)),
                  warning_messages=[line for line in output.splitlines() if line.startswith('WARNING:')],
                  reports={str(p.relative_to(ROOT)):digest(p) for p in work.iterdir()
                           if p.is_file() and p.suffix in ('.rpt','.json','.log','.xdc')})
    (work/'result.json').write_text(json.dumps(result,indent=2))
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--tops', nargs='+', default=['guided_core','moments5','moments_store_square','coefficient_box5','coefficient_box_queue'])
    parser.add_argument('--timeout', type=float, default=900)
    parser.add_argument('--route-core',action='store_true')
    parser.add_argument('--simulation-manifest',type=Path,default=ROOT/'reports/rtl/core_timing_fix_results.json')
    args=parser.parse_args()
    latencies=package_latencies()
    try:
        manifest=json.loads(args.simulation_manifest.read_text())
        checked_simulation_sources=verify_simulation_sources(manifest)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    if manifest.get('latencies') != latencies:
        parser.error('source latency package does not match the supplied simulation manifest')
    if not (BIN/'vivado.bat').is_file():
        parser.error(f'Vivado synthesis executable is unavailable: {BIN / "vivado.bat"}. Set VIVADO_BIN to the Vivado bin directory.')
    stamp=time.strftime('%Y%m%d-%H%M%S')
    work=ROOT/'build/regression/synthesis'/stamp
    sources=[*sorted((ROOT/'rtl').rglob('*.sv')),ROOT/'scripts/synth_core.tcl',Path(__file__),args.simulation_manifest]
    hashes={str(p.relative_to(ROOT)):digest(p) for p in sources}
    results=[]
    for top in args.tops:
        result=run(top,work/top,args.timeout,args.route_core and top=='guided_core'); results.append(result)
        print(top, 'PASS' if result['passed'] else 'FAIL',result['metrics'], result['failures'],flush=True)
    summary=dict(evidence_level='out-of-context synthesis; estimated interconnect, not routed or board validated',
                 commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                 parameters=dict(W=640,H=480,EXTRA_ALIGN=0,period_ns=10,input_max_ns=2,output_max_ns=2),
                 simulation_manifest=str(args.simulation_manifest),simulation_latencies=latencies,
                 checked_simulation_sources=checked_simulation_sources,
                 source_hashes=hashes, results=results)
    (work/'summary.json').write_text(json.dumps(summary,indent=2))
    print('SUMMARY',work/'summary.json',flush=True)
    return 0 if all(r['passed'] for r in results) else 1

if __name__=='__main__': raise SystemExit(main())
