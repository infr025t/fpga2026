"""Runtime harness contracts; mocked tools never count as RTL simulation."""
import argparse
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import zlib

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_runtime_tests as runner
import runtime_vectors as vectors


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def hashes_in(value):
    if isinstance(value, dict):
        return set().union(*(hashes_in(item) for item in value.values()))
    if isinstance(value, list):
        return set().union(*(hashes_in(item) for item in value))
    return {value} if isinstance(value, str) and len(value) == 64 else set()


class SimulatorFailureTests(unittest.TestCase):
    def invoke(self, replies, marker=None):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        source = root / 'fixture.sv'
        source.write_text('module fixture; endmodule\n', encoding='ascii')
        remaining = list(replies)

        def fake_tool(command, cwd, log, timeout):
            code, timed_out, output = remaining.pop(0)
            log.write(output)
            return code, timed_out

        def fake_subprocess(command, cwd, stdout, stderr, timeout):
            code, timed_out = fake_tool(command, cwd, stdout, timeout)
            if timed_out:
                raise subprocess.TimeoutExpired(command, timeout)
            return types.SimpleNamespace(returncode=code)

        with patch.object(runner.vivado_runner, '_run_tool', fake_tool), \
             patch.object(runner.subprocess, 'run', fake_subprocess):
            result = runner.simulate([source], 'fixture', root / 'run', 'iverilog',
                                     root / 'tool directory', 1, marker=marker)
        saved = json.loads((root / 'run/result.json').read_text(encoding='utf-8'))
        self.assertEqual(saved, result)
        return result, source

    def test_nonzero_compile_exit_stops_before_simulation(self):
        result, _ = self.invoke([(1, False, 'PASS fixture\n')])
        self.assertFalse(result['passed'])
        self.assertEqual(len(result['stages']), 1)

    def test_zero_exit_error_after_success_text_still_fails(self):
        result, _ = self.invoke([(0, False, ''),
                                 (0, False, 'PASS fixture\nERROR: deliberate failure\n')])
        self.assertFalse(result['passed'])

    def test_missing_or_misleading_pass_is_rejected(self):
        for output in ('ordinary completion\n', 'NOT PASS fixture\n'):
            with self.subTest(output=output):
                result, _ = self.invoke([(0, False, ''), (0, False, output)])
                self.assertFalse(result['passed'])
                self.assertEqual(result['reason'], 'missing PASS marker')

    def test_timeout_is_not_a_pass_even_after_pass_text(self):
        result, _ = self.invoke([(0, False, ''), (None, True, 'PASS fixture\n')])
        self.assertFalse(result['passed'])
        self.assertIn('timeout', result['reason'])
        self.assertIsNone(result['stages'][-1]['exit'])

    def test_named_marker_with_measured_fields_passes(self):
        result, _ = self.invoke([(0, False, ''),
                                 (0, False, 'PASS tb_runtime_core frames=4 pixels=256\n')],
                                marker='PASS tb_runtime_core')
        self.assertTrue(result['passed'])

    def test_actual_compilation_inputs_have_recorded_byte_hashes(self):
        result, source = self.invoke([(0, False, ''), (0, False, 'PASS fixture\n')])
        self.assertIn(digest(source), hashes_in(result))

    def test_existing_directory_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            canary = path / 'keep.txt'
            canary.write_text('old evidence', encoding='ascii')
            with patch.object(runner.vivado_runner, '_run_tool') as launch:
                with self.assertRaises(FileExistsError):
                    runner.simulate([], 'fixture', path, 'iverilog', path, 1)
            launch.assert_not_called()
            self.assertEqual(canary.read_text(encoding='ascii'), 'old evidence')


class ToolSelectionTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.iverilog = self.root / 'Icarus tools'
        self.vivado = self.root / 'Vivado tools'
        self.project = self.root / 'project'
        for directory in (self.iverilog, self.vivado, self.project):
            directory.mkdir()
        extension = '.exe' if os.name == 'nt' else ''
        for tool in ('iverilog', 'vvp'):
            (self.iverilog / (tool + extension)).touch()
        for tool in ('xvlog.bat', 'xelab.bat', 'xsim.bat'):
            (self.vivado / tool).touch()
        self.addCleanup(patch.stopall)
        patch.object(runner, 'ROOT', self.project).start()
        patch.object(runner.vivado_runner, 'BIN', self.vivado).start()
        patch.object(runner.shutil, 'which', return_value=None).start()
        patch.dict(os.environ, {'IVERILOG_BIN': str(self.iverilog)}).start()

    def args(self, **changes):
        values = dict(simulator='auto', iverilog_bin=None, vivado_bin=None)
        values.update(changes)
        return argparse.Namespace(**values)

    def test_explicit_icarus_wins_over_available_default_vivado(self):
        backend, directory = runner.discover(self.args(iverilog_bin=str(self.iverilog)))
        self.assertEqual((backend, directory), ('iverilog', self.iverilog))

    def test_explicit_vivado_selects_its_requested_directory(self):
        backend, directory = runner.discover(self.args(vivado_bin=str(self.vivado)))
        self.assertEqual((backend, directory), ('vivado', self.vivado))

    def test_bad_explicit_icarus_cannot_fall_back_to_environment(self):
        with self.assertRaises(ValueError):
            runner.discover(self.args(simulator='iverilog',
                                      iverilog_bin=str(self.root / 'missing')))

    def test_bad_explicit_vivado_cannot_fall_back_to_icarus(self):
        with self.assertRaises(ValueError):
            runner.discover(self.args(vivado_bin=str(self.root / 'missing')))


class ArgumentTests(unittest.TestCase):
    def assert_rejected(self, *arguments):
        with patch.object(sys, 'argv', ['runtime', '--output-dir', 'unused', *arguments]), \
             redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as failure:
            runner.arguments()
        self.assertEqual(failure.exception.code, 2)

    def test_conflicting_explicit_tools_are_rejected(self):
        self.assert_rejected('--iverilog-bin', 'a', '--vivado-bin', 'b')

    def test_explicit_tool_cannot_contradict_the_selected_backend(self):
        self.assert_rejected('--simulator', 'vivado', '--iverilog-bin', 'a')
        self.assert_rejected('--simulator', 'iverilog', '--vivado-bin', 'a')

    def test_duplicate_matrix_values_are_rejected(self):
        self.assert_rejected('--patterns', '0', '0')
        self.assert_rejected('--claims', '1', '1')

    def test_nonfinite_or_nonpositive_timeouts_are_rejected(self):
        for timeout in ('nan', 'inf', '0', '-1', '3601'):
            with self.subTest(timeout=timeout):
                self.assert_rejected('--timeout', timeout)


class VectorContractTests(unittest.TestCase):
    def test_serialized_pixels_crc_and_dimensions_match_the_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'vectors'
            report = vectors.generate(path, 17, 19, (2,))
            self.assertEqual((report['width'], report['height']), (17, 19))
            self.assertEqual(report['checked_pixels'], 4 * 9 * 11)
            self.assertEqual([item['mode'] for item in report['matrix']],
                             ['RAW', 'BASE', 'DENOISE', 'ENHANCE'])
            raw_crcs = [int(value, 16) for value in (path / 'raw_crc_p2.hex').read_text().split()]
            selected_crcs = [int(value, 16) for value in (path / 'selected_crc_p2.hex').read_text().split()]
            profile = json.loads((ROOT / 'model/profile.json').read_text(encoding='utf-8'))
            for frame, item in enumerate(report['matrix']):
                packed = np.array([int(value, 16) for value in
                    (path / f'expected_p2_f{frame}.hex').read_text().split()], dtype=np.uint32)
                self.assertEqual(packed.size, 9 * 11)
                raw = (packed >> 16).astype(np.uint8).tobytes()
                selected = (packed & 255).astype(np.uint8).tobytes()
                self.assertEqual(item['pixels'], packed.size)
                self.assertEqual(item['raw_crc'], zlib.crc32(raw))
                self.assertEqual(item['selected_crc'], zlib.crc32(selected))
                self.assertEqual(raw_crcs[frame], item['raw_crc'])
                self.assertEqual(selected_crcs[frame], item['selected_crc'])
                self.assertEqual(item['raw_sha256'], hashlib.sha256(raw).hexdigest())
                self.assertEqual(item['selected_sha256'], hashlib.sha256(selected).hexdigest())
                self.assertEqual(item['epsilon'], profile['epsilon'])
                if item['mode'] == 'RAW':
                    self.assertEqual(raw, selected)
                if item['mode'] == 'ENHANCE':
                    self.assertEqual((item['threshold'], item['gain']),
                                     (profile['T_E'], profile['G_E']))

    def test_duplicate_patterns_cannot_inflate_the_vector_report(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                vectors.generate(Path(folder) / 'vectors', 16, 16, (0, 0))


class MatrixEvidenceTests(unittest.TestCase):
    def test_vectors_are_reused_and_all_actual_inputs_are_bound(self):
        calls = []

        def fake_simulate(sources, top, directory, backend, binary_dir, timeout,
                          plusargs=(), marker=None):
            directory.mkdir(parents=True, exist_ok=False)
            calls.append(dict(sources=sources, plusargs=plusargs))
            return dict(top=top, passed=True, stages=[], work_dir=str(directory),
                        reason='PASS', simulation_summary=['PASS mocked tool-contract fixture'])

        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'run'
            arguments = ['runtime', '--suite', 'core', '--size', '16', '--align', 'both',
                         '--patterns', '0', '--claims', '0', '1', '2', '--output-dir', str(output)]
            with patch.object(sys, 'argv', arguments), \
                 patch.object(runner, 'discover', return_value=('iverilog', Path(folder))), \
                 patch.object(runner, 'simulate', fake_simulate), redirect_stdout(io.StringIO()):
                self.assertEqual(runner.main(), 0)
            summary = json.loads((output / 'summary.json').read_text(encoding='utf-8'))
            self.assertEqual(len(calls), 6)  # 2 latency configurations x 3 consumers
            self.assertEqual(len({tuple(call['plusargs']) for call in calls}), 1)
            self.assertEqual(len(summary['matrices']), 1)
            self.assertEqual(len(summary['matrices'][0]['matrix']), 4)
            self.assertEqual(summary['source_hashes']['scripts/run_core_tests.py'],
                             digest(ROOT / 'scripts/run_core_tests.py'))
            for path in (output / 'vectors_16').glob('*.hex'):
                key = path.relative_to(output).as_posix()
                self.assertEqual(summary['vector_hashes'][key], digest(path))
            wrappers = list(output.glob('core_*.sv'))
            self.assertEqual(len(wrappers), 6)
            for path in wrappers:
                self.assertEqual(summary['wrapper_hashes'][path.name], digest(path))


class InterruptionEvidenceTests(unittest.TestCase):
    def test_interrupt_retains_completed_cases_and_input_hashes(self):
        calls = []

        def interrupted_tool(sources, top, directory, *args, **kwargs):
            calls.append(directory)
            if len(calls) == 2:
                raise KeyboardInterrupt
            directory.mkdir()
            return dict(top=top, passed=True, stages=[], work_dir=str(directory),
                        reason='PASS', simulation_summary=['PASS mocked interruption fixture'])

        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'run'
            arguments = ['runtime', '--suite', 'core', '--size', '16', '--align', 'both',
                         '--patterns', '0', '--output-dir', str(output)]
            with patch.object(sys, 'argv', arguments), \
                 patch.object(runner, 'discover', return_value=('iverilog', Path(folder))), \
                 patch.object(runner, 'simulate', interrupted_tool), \
                 redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(runner.main(), 130)
            summary = json.loads((output / 'summary.json').read_text(encoding='utf-8'))
            self.assertEqual(summary['status'], 'interrupted')
            self.assertEqual(len(summary['results']), 1)
            self.assertTrue(summary['results'][0]['passed'])
            self.assertEqual(summary['active_case'], 'core_16_a1_p0_c0')
            self.assertTrue(summary['vector_hashes'])
            self.assertTrue(summary['wrapper_hashes'])
            self.assertTrue(summary['source_hashes'])


if __name__ == '__main__':
    unittest.main()
