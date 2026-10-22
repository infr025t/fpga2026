"""Run RTL simulations and Python tests without replacing historical evidence.

Tool discovery: explicit --*-bin, environment, PATH, then common install paths.
Use --python-only to run the PC tests on a machine without an RTL simulator.
"""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL_TESTS = ('fifo_capture', 'camera_config', 'camera_readback', 'camera_monitor',
             'image_core', 'target_stats', 'transport', 'target_transport',
             'output_transport', 'output_budget', 'top', 'top_target', 'top_output',
             'camera_retry', 'top_recovery', 'top_preview')
WIRE_STREAMS = {
    'target_transport': ('target_wire.bin', 6),
    'top_target': ('top_target_wire.bin', 4),
    'output_transport': ('output_wire.bin', 6),
    'top_output': ('top_output_wire.bin', 5),
    'top_recovery': ('top_recovery_wire.bin', 3),
    'top_preview': ('top_preview_wire.bin', 13),
}
ERROR_LINE = re.compile(r'^\s*(?:fatal|error)\s*(?::|\[)', re.I | re.M)
PASS_LINE = re.compile(r'^PASS(?:\b|_)', re.M)


class RegressionError(RuntimeError):
    """An actionable regression failure, shown without a Python traceback."""


def tool_names(name):
    suffixes = ('.bat', '.exe', '') if os.name == 'nt' else ('',)
    return tuple(name + suffix for suffix in suffixes)


def tools_in(directory, names):
    """Accept either an install root or its bin directory, as a complete set."""
    directory = Path(directory).expanduser()
    for candidate in (directory, directory / 'bin'):
        found = {}
        for name in names:
            path = next((candidate / filename for filename in tool_names(name)
                         if (candidate / filename).is_file()), None)
            if path is None:
                break
            found[name] = path.resolve()
        if len(found) == len(names):
            return found
    return None


def common_install_dirs(simulator):
    """Only inspect known install layouts; do not recursively scan user disks."""
    if os.name != 'nt':
        if simulator == 'vivado':
            for base in (Path('/opt/Xilinx/Vivado'), Path('/tools/Xilinx/Vivado')):
                yield from sorted(base.glob('*/bin'), reverse=True)
        return
    for drive in ('C:', 'D:', 'E:'):
        if simulator == 'vivado':
            for base in ('Xilinx/Vivado', 'AMD/Vivado', 'Vivado'):
                root = Path(drive + '/') / base
                yield from sorted(root.glob('*/bin'), reverse=True)
                yield from sorted(root.glob('*/Vivado/bin'), reverse=True)
            root = Path(drive + '/') / 'AMDDesignTools'
            yield from sorted(root.glob('*/Vivado/bin'), reverse=True)
        else:
            for base in ('iverilog/bin', 'Icarus Verilog/bin',
                         'Program Files/iverilog/bin'):
                yield Path(drive + '/') / base


def discover_tools(explicit, env_names, names, simulator):
    if explicit is not None:
        result = tools_in(explicit, names)
        if result is None:
            raise RegressionError(
                f'{simulator}: {explicit} must contain {", ".join(names)} '
                '(or a bin directory containing them).')
        return result
    for env_name in env_names:
        value = os.environ.get(env_name)
        if value:
            result = tools_in(value, names)
            if result:
                return result
    found = {}
    for name in names:
        path = next((p for filename in tool_names(name)
                     if (p := shutil.which(filename))), None)
        if path is None:
            break
        found[name] = Path(path).resolve()
    if len(found) == len(names):
        return found
    for directory in common_install_dirs(simulator):
        result = tools_in(directory, names)
        if result:
            return result
    return None


def discover_simulator(args):
    selected = args.simulator
    if args.vivado_bin is not None:
        selected = 'vivado'
    elif args.iverilog_bin is not None:
        selected = 'iverilog'
    if selected in ('auto', 'vivado'):
        found = discover_tools(args.vivado_bin,
                               ('VIVADO_BIN', 'XILINX_VIVADO', 'VIVADO_HOME'),
                               ('xvlog', 'xelab', 'xsim'), 'vivado')
        if found:
            return 'vivado', found
    if selected in ('auto', 'iverilog'):
        found = discover_tools(args.iverilog_bin, ('IVERILOG_BIN',),
                               ('iverilog', 'vvp'), 'iverilog')
        if found:
            return 'iverilog', found
    raise RegressionError(
        f'No complete {selected} RTL simulator found. Use --vivado-bin BIN '
        '(or XILINX_VIVADO/VIVADO_BIN), --iverilog-bin BIN '
        '(or IVERILOG_BIN), or put the tools on PATH. '
        'Use --python-only to run the PC tests without RTL simulation.')


def run(command, cwd, log, timeout):
    command = [str(c) for c in command]
    try:
        result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, encoding='utf-8',
                                errors='replace', timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ''
        if isinstance(output, bytes):
            output = output.decode('utf-8', errors='replace')
        log.write_text(output + f'\nTIMEOUT after {timeout:g} seconds\n',
                       encoding='utf-8')
        raise RegressionError(f'Timeout after {timeout:g} seconds; see {log}') from exc
    except OSError as exc:
        log.write_text(str(exc) + '\n', encoding='utf-8')
        raise RegressionError(f'Could not start {command[0]}: {exc}; see {log}') from exc
    log.write_text(result.stdout, encoding='utf-8')
    # Some simulators report $fatal/$error but return exit status zero.
    if result.returncode or ERROR_LINE.search(result.stdout):
        # Keep the full UTF-8 log even when a legacy Windows console cannot
        # print a tool's Unicode diagnostics. Reporting must not mask failure.
        printable = result.stdout
        encoding = getattr(sys.stdout, 'encoding', None)
        if encoding:
            printable = printable.encode(encoding, errors='backslashreplace').decode(encoding)
        print(printable, end='' if printable.endswith('\n') else '\n')
        raise RegressionError(f'Command failed (exit {result.returncode}); see {log}')
    return result.stdout


def run_python_tests(output, timeout):
    for directory, pattern, logfile in (
            ('pc', 'test_*.py', 'python_tests.log'),
            ('scripts', 'test_*.py', 'runner_tests.log')):
        run([sys.executable, '-B', '-m', 'unittest', 'discover',
             '-s', ROOT / directory, '-p', pattern, '-v'],
            ROOT, output / logfile, timeout)
    print('PASS Python receiver and regression-runner unittest suites', flush=True)


def run_rtl(name, simulator, tools, output, timeout):
    dest = output / ('verify_' + name)
    dest.mkdir()
    sources = sorted((ROOT / 'rtl').glob('*.sv')) + [ROOT / 'sim' / f'tb_{name}.sv']
    if simulator == 'vivado':
        run([tools['xvlog'], '-sv', *sources], dest, dest / 'compile.log', timeout)
        run([tools['xelab'], f'tb_{name}', '-s', 'test'],
            dest, dest / 'elaborate.log', timeout)
        command = [tools['xsim'], 'test', '-runall']
    else:
        image = dest / 'test.vvp'
        run([tools['iverilog'], '-g2012', '-s', f'tb_{name}',
             '-o', image, *sources], dest, dest / 'compile.log', timeout)
        command = [tools['vvp'], image]
    result = run(command, dest, dest / 'simulate.log', timeout)
    if not PASS_LINE.search(result):
        raise RegressionError(f'Missing PASS marker; see {dest / "simulate.log"}')
    print(next(line for line in result.splitlines() if PASS_LINE.match(line)), flush=True)
    return dest


def existing_wire():
    candidates = sorted((ROOT / 'build' / 'regression').glob('*/verify_transport/wire.bin'),
                        reverse=True)
    candidates.append(ROOT / 'build' / 'verify_transport' / 'wire.bin')
    return next((path for path in candidates if path.is_file()), None)


def arguments(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python-only', action='store_true',
                        help='run Python suites and any available wire cross-check; skip RTL')
    parser.add_argument('--simulator', choices=('auto', 'vivado', 'iverilog'), default='auto')
    parser.add_argument('--vivado-bin', type=Path, help='Vivado installation root or bin directory')
    parser.add_argument('--iverilog-bin', type=Path, help='Icarus installation root or bin directory')
    parser.add_argument('--output-dir', type=Path,
                        help='new output directory (default: build/regression/TIMESTAMP)')
    parser.add_argument('--wire', type=Path,
                        help='existing wire stream to check (default: this run or latest saved wire.bin)')
    parser.add_argument('--wire-count', type=int, default=2,
                        help='number of valid frames required from wire stream (default: 2)')
    parser.add_argument('--tests', nargs='+', choices=RTL_TESTS, default=RTL_TESTS,
                        help=f'RTL testbenches to run (default: all {len(RTL_TESTS)})')
    parser.add_argument('--timeout', type=float, default=180,
                        help='per-command timeout in seconds (default: 180)')
    args = parser.parse_args(argv)
    if args.timeout <= 0 or args.wire_count <= 0:
        parser.error('--timeout and --wire-count must be positive')
    if args.vivado_bin is not None and args.iverilog_bin is not None:
        parser.error('choose only one of --vivado-bin and --iverilog-bin')
    if args.vivado_bin is not None and args.simulator == 'iverilog':
        parser.error('--vivado-bin conflicts with --simulator iverilog')
    if args.iverilog_bin is not None and args.simulator == 'vivado':
        parser.error('--iverilog-bin conflicts with --simulator vivado')
    return args


def main(argv=None):
    args = arguments(argv)
    if args.wire is not None and not args.wire.is_file():
        print(f'FAIL: Requested wire stream does not exist: {args.wire}', file=sys.stderr)
        return 1
    output = (args.output_dir or ROOT / 'build' / 'regression' /
              datetime.now().strftime('%Y%m%d_%H%M%S_%f')).resolve()
    try:
        output.mkdir(parents=True, exist_ok=False)
    except OSError as exc:
        print(f'FAIL: Need a new writable output directory: {output}: {exc}', file=sys.stderr)
        return 1
    print(f'Output: {output}', flush=True)
    summary = {'status': 'running', 'output': str(output),
               'python': {'status': 'running'}, 'rtl': {'status': 'pending'},
               'wire': {'status': 'pending'}, 'feature_wires': []}
    wire = args.wire.resolve() if args.wire is not None else None
    try:
        run_python_tests(output, args.timeout)
        summary['python'] = {'status': 'passed'}
        if args.python_only:
            summary['rtl'] = {'status': 'skipped', 'reason': '--python-only'}
            print('SKIP RTL simulation (--python-only)', flush=True)
        else:
            summary['rtl'] = {'status': 'running'}
            simulator, tools = discover_simulator(args)
            summary['rtl'] = {'status': 'running', 'simulator': simulator,
                              'tools': {k: str(v) for k, v in tools.items()}, 'tests': []}
            print(f'RTL simulator: {simulator}', flush=True)
            for name in dict.fromkeys(args.tests):
                dest = run_rtl(name, simulator, tools, output, args.timeout)
                summary['rtl']['tests'].append(name)
                if name == 'transport' and wire is None:
                    wire = dest / 'wire.bin'
                    if not wire.is_file():
                        raise RegressionError(f'tb_transport did not create {wire}')
                if name in WIRE_STREAMS:
                    filename, count = WIRE_STREAMS[name]
                    feature_wire = dest / filename
                    if not feature_wire.is_file():
                        raise RegressionError(f'tb_{name} did not create {feature_wire}')
                    summary['feature_wires'].append({
                        'status': 'pending', 'name': name, 'input': str(feature_wire),
                        'required_frames': count})
            summary['rtl']['status'] = 'passed'
        wire = wire or existing_wire()
        if wire is None:
            summary['wire'] = {'status': 'skipped', 'reason': 'No recorded wire.bin is available'}
            print('SKIP wire cross-check: no wire.bin available; use --wire PATH or run transport RTL.',
                  flush=True)
        else:
            summary['wire'] = {'status': 'running', 'input': str(wire),
                               'required_frames': args.wire_count}
            run([sys.executable, '-B', ROOT / 'pc' / 'receiver.py', '--input', wire,
                 '--out', output / 'verified_frames', '--count', args.wire_count],
                ROOT, output / 'wire_crosscheck.log', args.timeout)
            summary['wire']['status'] = 'passed'
            print(f'PASS receiver wire-stream cross-check ({args.wire_count} frames): {wire}',
                  flush=True)
        for feature in summary['feature_wires']:
            feature['status'] = 'running'
            run([sys.executable, '-B', ROOT / 'pc' / 'receiver.py', '--input', feature['input'],
                 '--out', output / ('verified_' + feature['name']),
                 '--count', feature['required_frames']],
                ROOT, output / (feature['name'] + '_crosscheck.log'), args.timeout)
            feature['status'] = 'passed'
            print(f'PASS protocol wire-stream cross-check: {feature["name"]}', flush=True)
        summary['status'] = 'passed'
        print('PASS requested regression checks; see summary.json for passes and skips.', flush=True)
        return 0
    except (RegressionError, OSError) as exc:
        summary['status'] = 'failed'
        summary['error'] = str(exc)
        for section in ('python', 'rtl', 'wire'):
            if summary[section]['status'] == 'running':
                summary[section]['status'] = 'failed'
        for feature in summary['feature_wires']:
            if feature['status'] == 'running':
                feature['status'] = 'failed'
        print(f'FAIL: {exc}', file=sys.stderr)
        return 1
    finally:
        (output / 'summary.json').write_text(
            json.dumps(summary, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


if __name__ == '__main__':
    sys.exit(main())
