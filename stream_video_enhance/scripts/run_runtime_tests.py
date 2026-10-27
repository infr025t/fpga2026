"""Run synchronous-runtime benches with Icarus or Vivado and a frozen oracle.

No board synthesis, model search, screen, or camera hardware is exercised.
Each output directory must be new; raw tool outputs and source hashes are kept.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import run_core_tests as vivado_runner

ROOT = Path(__file__).resolve().parents[1]


def discover(args):
    if args.iverilog_bin and args.vivado_bin:
        raise ValueError('Choose only one of --iverilog-bin and --vivado-bin.')
    if args.iverilog_bin and args.simulator == 'vivado':
        raise ValueError('--iverilog-bin conflicts with --simulator vivado.')
    if args.vivado_bin and args.simulator == 'iverilog':
        raise ValueError('--vivado-bin conflicts with --simulator iverilog.')
    selected = 'iverilog' if args.iverilog_bin else 'vivado' if args.vivado_bin else args.simulator
    if selected != 'iverilog':
        directory = Path(args.vivado_bin) if args.vivado_bin else vivado_runner.BIN
        if not vivado_runner.missing_simulator_tools(directory):
            return 'vivado', directory
        if selected == 'vivado':
            raise ValueError(vivado_runner.simulator_unavailable_message(
                vivado_runner.missing_simulator_tools(directory)))
    candidates = []
    if args.iverilog_bin:
        directory = Path(args.iverilog_bin)
        extension = '.exe' if os.name == 'nt' else ''
        if not all((directory / (name + extension)).is_file() for name in ('iverilog', 'vvp')):
            raise ValueError('--iverilog-bin must contain both iverilog and vvp.')
        return 'iverilog', directory
    if os.environ.get('IVERILOG_BIN'):
        candidates.append(Path(os.environ['IVERILOG_BIN']))
    on_path = shutil.which('iverilog')
    if on_path:
        candidates.append(Path(on_path).parent)
    hint = ROOT.parent / '.tools/iverilog-runtime.txt'
    if hint.is_file():
        candidates.append(Path(hint.read_text(encoding='utf-8').strip()))
    extension = '.exe' if os.name == 'nt' else ''
    for directory in candidates:
        if all((directory / (name + extension)).is_file() for name in ('iverilog', 'vvp')):
            return 'iverilog', directory
    raise ValueError('No simulator found. Set --iverilog-bin or IVERILOG_BIN; '
                     'alternatively set --vivado-bin or VIVADO_BIN.')


def simulate(sources, top, directory, backend, binary_dir, timeout, plusargs=(), marker=None):
    directory.mkdir(parents=True, exist_ok=False)
    if backend == 'vivado':
        vivado_runner.BIN = binary_dir
        result = vivado_runner.run_bench(sources, top, directory, timeout, marker, plusargs)
        result['source_hashes'] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        return result
    extension = '.exe' if os.name == 'nt' else ''
    image = directory / 'simulation.vvp'
    commands = [('compile', [str(binary_dir / ('iverilog' + extension)), '-g2012', '-s', top,
                              '-o', str(image), *map(str, sources)]),
                ('simulate', [str(binary_dir / ('vvp' + extension)), str(image),
                              *('+' + arg for arg in plusargs)])]
    result = dict(top=top, passed=False, stages=[], work_dir=str(directory))
    output = ''
    for name, command in commands:
        log_path = directory / (name + '.log')
        start = time.monotonic()
        with log_path.open('w', encoding='utf-8') as log:
            if os.name == 'nt':
                code, timed_out = vivado_runner._run_tool(command, directory, log, timeout)
            else:
                try:
                    code = subprocess.run(command, cwd=directory, stdout=log,
                                          stderr=subprocess.STDOUT, timeout=timeout).returncode
                    timed_out = False
                except subprocess.TimeoutExpired:
                    code, timed_out = None, True
        output = log_path.read_text(encoding='utf-8', errors='replace')
        result['stages'].append(dict(name=name, command=command, exit=code, log=str(log_path),
                                    seconds=round(time.monotonic() - start, 3)))
        if timed_out or code != 0 or vivado_runner.ERROR.search(output):
            result['reason'] = name + (' timeout' if timed_out else ' failed')
            break
    else:
        result['passed'] = vivado_runner.has_pass_marker(output, marker or 'PASS ' + top)
        result['reason'] = 'PASS' if result['passed'] else 'missing PASS marker'
    result['simulation_summary'] = [line for line in output.splitlines() if line.startswith('PASS ')]
    result['source_hashes'] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulator', choices=('auto', 'iverilog', 'vivado'), default='auto')
    parser.add_argument('--iverilog-bin')
    parser.add_argument('--vivado-bin')
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--suite', choices=('all', 'crc', 'ingress', 'core', 'recovery'), default='all')
    parser.add_argument('--size', choices=('all', '16', '17', 'vga'), default='16')
    parser.add_argument('--align', choices=('both', '0', '1'), default='both')
    parser.add_argument('--patterns', type=int, choices=range(4), nargs='+', default=list(range(4)))
    parser.add_argument('--claims', type=int, choices=range(3), nargs='+', default=[0])
    parser.add_argument('--timeout', type=float, default=600)
    args = parser.parse_args()
    if args.iverilog_bin and args.vivado_bin:
        parser.error('Choose only one of --iverilog-bin and --vivado-bin.')
    if (args.iverilog_bin and args.simulator == 'vivado') or (args.vivado_bin and args.simulator == 'iverilog'):
        parser.error('Explicit tool directory conflicts with --simulator.')
    if not 0 < args.timeout <= 3600:
        parser.error('--timeout must be positive and at most 3600 seconds')
    if len(set(args.patterns)) != len(args.patterns) or len(set(args.claims)) != len(args.claims):
        parser.error('--patterns and --claims must not contain duplicate values')
    if args.suite == 'recovery' and args.size == 'vga':
        parser.error('Recovery benches use --size 16, 17 or all; VGA is covered by --suite core.')
    if args.suite in ('all', 'recovery') and 0 not in args.patterns:
        parser.error('The recovery bench requires pattern 0 in --patterns.')
    return args


def main():
    args = arguments()
    try:
        backend, binary_dir = discover(args)
        output = args.output_dir.resolve()
        output.mkdir(parents=True, exist_ok=False)
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 2
    packages = [ROOT / 'rtl' / name for name in ('core_latency_pkg.sv', 'video_runtime_pkg.sv')]
    sources = packages + [p for p in sorted((ROOT / 'rtl').glob('*.sv')) if p not in packages]
    source_files = sources + list((ROOT / 'sim').glob('tb_*runtime*.sv')) + [ROOT / 'sim/tb_core_crc.sv',
        Path(__file__).resolve(), ROOT / 'scripts/run_core_tests.py',
        ROOT / 'scripts/runtime_vectors.py', ROOT / 'model/reference.py']
    summary = dict(status='running', simulator=backend, tools=str(binary_dir), results=[],
                   source_hashes={p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in source_files}, matrices=[], vector_hashes={}, wrapper_hashes={})
    print('Output:', output, flush=True)

    def checkpoint():
        (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')

    checkpoint()

    def run(top, destination, extra_sources=(), plusargs=(), marker=None):
        summary['active_case'] = destination
        checkpoint()  # Preserve provenance even if the first long case is interrupted.
        result = simulate([*sources, *extra_sources], top, output / destination,
                          backend, binary_dir, args.timeout, plusargs, marker)
        result['source_hashes'] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in [*sources, *extra_sources]}
        summary['results'].append(result)
        summary.pop('active_case', None)
        checkpoint()
        print('\n'.join(result['simulation_summary']) or result['reason'], flush=True)
        if not result['passed']:
            raise RuntimeError(f'{top}: {result["reason"]}; inspect {result["work_dir"]}')

    try:
        if args.suite in ('all', 'crc'):
            run('tb_core_crc', 'crc', [ROOT / 'sim/tb_core_crc.sv'])
        if args.suite in ('all', 'ingress'):
            run('tb_runtime_ingress', 'ingress', [ROOT / 'sim/tb_runtime_ingress.sv'])
        if args.suite in ('all', 'core', 'recovery'):
            from runtime_vectors import generate
            for name, width, height in [('16', 16, 16), ('17', 17, 19), ('vga', 640, 480)]:
                if args.size not in ('all', name):
                    continue
                vectors = output / ('vectors_' + name)
                summary['matrices'].append(generate(vectors, width, height, args.patterns))
                summary['vector_hashes'].update({p.relative_to(output).as_posix():
                    hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(vectors.iterdir()) if p.is_file()})
                for align in (0, 1):
                    if args.align not in ('both', str(align)):
                        continue
                    if args.suite in ('all', 'recovery') and width<640:
                        case = f'recovery_{name}_a{align}'
                        wrapper = output / (case + '.sv')
                        wrapper.write_text('module tb_selected; tb_runtime_recovery #('
                            f'.W({width}),.H({height}),.EXTRA_ALIGN({align})) test(); endmodule\n', encoding='ascii')
                        summary['wrapper_hashes'][wrapper.relative_to(output).as_posix()] = hashlib.sha256(wrapper.read_bytes()).hexdigest()
                        run('tb_selected', case, [ROOT / 'sim/tb_runtime_recovery.sv', wrapper],
                            ['VECTORS=' + vectors.as_posix()], 'PASS tb_runtime_recovery')
                    if args.suite == 'recovery':
                        continue
                    for pattern in dict.fromkeys(args.patterns):
                        for claim in dict.fromkeys(args.claims):
                            case = f'core_{name}_a{align}_p{pattern}_c{claim}'
                            wrapper = output / (case + '.sv')
                            wrapper.write_text('module tb_selected; tb_runtime_core #('
                                f'.W({width}),.H({height}),.PATTERN_ID({pattern}),'
                                f'.EXTRA_ALIGN({align}),.CLAIM_MODE({claim})) test(); endmodule\n',
                                encoding='ascii')
                            summary['wrapper_hashes'][wrapper.relative_to(output).as_posix()] = hashlib.sha256(wrapper.read_bytes()).hexdigest()
                            run('tb_selected', case, [ROOT / 'sim/tb_runtime_core.sv', wrapper],
                                ['VECTORS=' + vectors.as_posix()], 'PASS tb_runtime_core')
        summary['status'] = 'passed'
        print('PASS requested runtime checks', flush=True)
        return 0
    except KeyboardInterrupt:
        summary['status'] = 'interrupted'
        print('Runtime checks interrupted; completed results are retained.', file=sys.stderr)
        return 130
    except (RuntimeError, OSError) as error:
        summary['status'] = 'failed'
        summary['error'] = str(error)
        print(str(error), file=sys.stderr)
        return 1
    finally:
        checkpoint()


if __name__ == '__main__':
    raise SystemExit(main())
