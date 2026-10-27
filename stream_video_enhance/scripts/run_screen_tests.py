"""Exercise the NT35510 write bus, initialization and independent panel model.

No FPGA bitstream or physical screen is exercised. The output directory must
be new. Commands, raw logs, vectors and exact source hashes are retained.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

import generate_nt35510_rom as generator
from run_runtime_tests import discover, simulate

ROOT = Path(__file__).resolve().parents[1]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', choices=('auto', 'iverilog', 'vivado'), default='auto')
    parser.add_argument('--iverilog-bin')
    parser.add_argument('--vivado-bin')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--suite', choices=('all', 'bus', 'init', 'window', 'display'), default='all')
    parser.add_argument('--size', choices=('all', 'small', 'full'), default='all')
    parser.add_argument('--timeout', type=float, default=600)
    args = parser.parse_args(argv)
    if not 0 < args.timeout <= 3600:
        parser.error('--timeout must be positive and at most 3600 seconds')
    try:
        backend, binary_dir = discover(args)
        profile, rows = generator.load_profile()
        if generator.ROM.read_bytes() != generator.render_rom(profile, rows).encode('utf-8'):
            raise ValueError('initialization ROM differs from the audited profile; run generator --check')
        output = args.output_dir.resolve()
        output.mkdir(parents=True, exist_ok=False)
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 2

    sources = sorted((ROOT / 'rtl').glob('nt35510*.sv'))
    provenance = [*sources, *sorted((ROOT / 'sim').glob('tb_nt35510*.sv')),
                  generator.PROFILE, generator.ROM, Path(__file__).resolve(),
                  ROOT / 'scripts/generate_nt35510_rom.py',
                  ROOT / 'scripts/run_runtime_tests.py', ROOT / 'scripts/run_core_tests.py']
    summary = dict(status='running', simulator=backend, tools=str(binary_dir), results=[],
                   scope='standalone write-only panel bring-up; no physical hardware validation',
                   source_hashes={p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in provenance})

    def checkpoint():
        (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')

    def run(top, bench, case, marker=None, rejection=None, extra=()):
        summary['active_case'] = case
        checkpoint()
        directory = output / case
        result = simulate([*sources, ROOT / 'sim' / bench], top, directory,
                          backend, binary_dir, args.timeout,
                          ['VECTORS=' + (output / 'vectors').as_posix(),
                           'OUTPUT=' + directory.as_posix(), *extra], marker)
        if rejection:
            stages = result['stages']
            log = Path(stages[-1]['log']).read_text(encoding='utf-8', errors='replace') if stages else ''
            compile_ok = len(stages) >= 2 and all(s['exit'] == 0 for s in stages[:-1])
            # A timeout, compile failure, or unrelated fatal cannot satisfy a negative case.
            result['expected_rejection'] = rejection
            result['accepted_expected_rejection'] = (compile_ok and stages[-1]['exit'] is not None
                and stages[-1]['exit'] != 0
                and re.search(r'(?m)^\s*(?:FATAL|Fatal):[^\n]*' + re.escape(rejection), log) is not None)
            passed = result['accepted_expected_rejection']
        else:
            passed = result['passed']
        result['case_passed'] = passed
        summary['results'].append(result)
        summary.pop('active_case', None)
        checkpoint()
        print(('PASS expected rejection ' + top if rejection and passed else
               '\n'.join(result.get('simulation_summary', [])) or result['reason']), flush=True)
        if not passed:
            raise RuntimeError(f'{top}: unexpected result; inspect {directory}')

    checkpoint()
    try:
        generator.export_expected(output / 'vectors', profile, rows)
        summary['vector_hashes'] = {p.relative_to(output).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                   for p in (output / 'vectors').iterdir() if p.is_file()}
        if args.suite in ('all', 'bus'):
            run('tb_nt35510_bus8', 'tb_nt35510_bus8.sv', 'bus')
            for kind in ('setup', 'low', 'hold', 'gap'):
                run('tb_nt35510_bus8_bad_' + kind, 'tb_nt35510_bus8.sv', 'reject_' + kind,
                    rejection='unsafe NT35510 timing parameters for 100 MHz')
        if args.suite in ('all', 'init'):
            run('tb_nt35510_init', 'tb_nt35510_init.sv', 'init')
        if args.suite in ('all', 'window'):
            run('tb_nt35510_window', 'tb_nt35510_window.sv', 'window')
        if args.suite in ('all', 'display'):
            run('tb_nt35510_bringup', 'tb_nt35510_display.sv', 'bringup')
            if args.size in ('all', 'small'):
                run('tb_nt35510_display', 'tb_nt35510_display.sv', 'display_small')
            if args.size in ('all', 'full'):
                run('tb_nt35510_display_full', 'tb_nt35510_display.sv', 'display_full',
                    marker='PASS tb_nt35510_display')
        summary['status'] = 'passed'
        print('PASS requested screen checks', flush=True)
        return 0
    except KeyboardInterrupt:
        summary['status'] = 'interrupted'
        return 130
    except (OSError, ValueError, RuntimeError) as error:
        summary['status'] = 'failed'
        summary['error'] = str(error)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        checkpoint()


if __name__ == '__main__':
    raise SystemExit(main())
