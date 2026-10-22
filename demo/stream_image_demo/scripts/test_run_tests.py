"""Regression-runner checks using temporary tools and output directories."""
import contextlib
import binascii
import io
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest import mock

import run_tests


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def fake_tools(self, names, directory=None):
        directory = directory or self.root / 'tool installation with spaces' / 'bin'
        directory.mkdir(parents=True)
        for name in names:
            (directory / run_tests.tool_names(name)[0]).write_text('', encoding='utf-8')
        return directory

    def test_explicit_install_root_and_environment_discovery(self):
        names = ('xvlog', 'xelab', 'xsim')
        directory = self.fake_tools(names)
        tools = run_tests.discover_tools(directory.parent, (), names, 'vivado')
        self.assertEqual(tools['xsim'].parent, directory.resolve())
        with mock.patch.dict(run_tests.os.environ, {'XILINX_VIVADO': str(directory.parent)}, clear=True):
            tools = run_tests.discover_tools(None, ('XILINX_VIVADO',), names, 'vivado')
        self.assertEqual(tools['xvlog'].parent, directory.resolve())

    def test_incomplete_explicit_install_fails_without_fallback(self):
        directory = self.fake_tools(('xvlog',))
        with self.assertRaisesRegex(run_tests.RegressionError, 'must contain xvlog, xelab, xsim'):
            run_tests.discover_tools(directory, (), ('xvlog', 'xelab', 'xsim'), 'vivado')

    def test_icarus_path_discovery_requires_both_tools(self):
        directory = self.fake_tools(('iverilog', 'vvp'))
        with mock.patch.object(run_tests.shutil, 'which',
                               side_effect=lambda name: str(directory / name)
                               if (directory / name).is_file() else None):
            found = run_tests.discover_tools(None, (), ('iverilog', 'vvp'), 'iverilog')
        self.assertEqual(set(found), {'iverilog', 'vvp'})

    def test_zero_exit_fatal_and_error_are_failures(self):
        for output in ('FATAL: tb.sv:4: timeout\n', 'Fatal: bad frame\n',
                       'ERROR: [XSIM 1] failed\n'):
            with self.subTest(output=output), mock.patch.object(
                    run_tests.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, output)):
                with contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(run_tests.RegressionError):
                        run_tests.run(['simulator'], self.root, self.root / 'sim.log', 1)
            self.assertEqual((self.root / 'sim.log').read_text(encoding='utf-8'), output)

    def test_error_handling_pass_text_is_not_a_failure(self):
        output = 'PASS camera_config NACK/error handling; 0 errors\n'
        with mock.patch.object(run_tests.subprocess, 'run',
                               return_value=subprocess.CompletedProcess([], 0, output)):
            self.assertEqual(run_tests.run(['simulator'], self.root, self.root / 'sim.log', 1), output)

    def test_unicode_tool_failure_keeps_log_and_failed_summary_on_legacy_console(self):
        output = self.root / 'unicode results'
        message = 'ERROR: tool diagnostic \ufffd\U0001f4f7\n'
        console_bytes = io.BytesIO()
        console = io.TextIOWrapper(console_bytes, encoding='gbk', errors='strict')
        def fail_python_tests(dest, timeout):
            run_tests.run(['simulator'], self.root, dest / 'python_tests.log', timeout)
        with mock.patch.object(run_tests, 'run_python_tests', side_effect=fail_python_tests), \
                mock.patch.object(run_tests.subprocess, 'run',
                                  return_value=subprocess.CompletedProcess([], 1, message)), \
                contextlib.redirect_stdout(console), contextlib.redirect_stderr(io.StringIO()):
            result = run_tests.main(['--python-only', '--output-dir', str(output)])
        console.flush()
        self.assertEqual(result, 1)
        summary = json.loads((output / 'summary.json').read_text(encoding='utf-8'))
        self.assertEqual(summary['status'], 'failed')
        self.assertEqual(summary['python']['status'], 'failed')
        self.assertEqual((output / 'python_tests.log').read_text(encoding='utf-8'), message)
        self.assertIn(b'\\ufffd\\U0001f4f7', console_bytes.getvalue())
        console.close()

    def test_timeout_retains_partial_output(self):
        with mock.patch.object(run_tests.subprocess, 'run',
                               side_effect=subprocess.TimeoutExpired(['simulator'], 1, b'partial output')):
            with self.assertRaisesRegex(run_tests.RegressionError, 'Timeout'):
                run_tests.run(['simulator'], self.root, self.root / 'sim.log', 1)
        self.assertIn('partial output', (self.root / 'sim.log').read_text(encoding='utf-8'))

    def test_python_only_without_wire_passes_and_reports_skips(self):
        output = self.root / 'new results'
        with mock.patch.object(run_tests, 'run_python_tests') as python_tests, \
                mock.patch.object(run_tests, 'existing_wire', return_value=None), \
                mock.patch.object(run_tests, 'discover_simulator') as discover, \
                contextlib.redirect_stdout(io.StringIO()) as stdout:
            result = run_tests.main(['--python-only', '--output-dir', str(output)])
        self.assertEqual(result, 0)
        python_tests.assert_called_once()
        discover.assert_not_called()
        summary = json.loads((output / 'summary.json').read_text(encoding='utf-8'))
        self.assertEqual(summary['python']['status'], 'passed')
        self.assertEqual(summary['rtl']['status'], 'skipped')
        self.assertEqual(summary['wire']['status'], 'skipped')
        self.assertIn('SKIP wire cross-check', stdout.getvalue())

    def test_explicit_missing_wire_fails_before_running_tests(self):
        with mock.patch.object(run_tests, 'run_python_tests') as python_tests, \
                contextlib.redirect_stderr(io.StringIO()) as stderr:
            result = run_tests.main(['--python-only', '--wire', str(self.root / 'missing.bin')])
        self.assertEqual(result, 1)
        python_tests.assert_not_called()
        self.assertIn('Requested wire stream does not exist', stderr.getvalue())

    def test_explicit_wire_is_really_decoded(self):
        output = self.root / 'results'
        wire = self.root / 'wire.bin'
        wire.write_bytes(b'not a real packet')
        # Keep receiver.py as a real subprocess: success must depend on valid frames.
        with mock.patch.object(run_tests, 'run_python_tests'), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = run_tests.main(['--python-only', '--wire', str(wire), '--output-dir', str(output)])
        self.assertEqual(result, 1)
        summary = json.loads((output / 'summary.json').read_text(encoding='utf-8'))
        self.assertEqual(summary['wire']['status'], 'failed')
        self.assertIn('requested frame count', (output / 'wire_crosscheck.log').read_text(encoding='utf-8'))

    def test_valid_explicit_wire_writes_two_decoded_frames(self):
        output = self.root / 'valid results'
        wire = self.root / 'wire.bin'
        packets = []
        for frame_id in (7, 8):
            header = struct.pack('<4sBBHHHIIIII', b'FPG1', 1, 0, 4, 2,
                                 180, frame_id, 8, 0, 0, 0)
            body = header[4:] + b'abcdefgh'
            packets.append(header + b'abcdefgh' +
                           struct.pack('<H', binascii.crc_hqx(body, 0xffff)))
        wire.write_bytes(b''.join(packets))
        with mock.patch.object(run_tests, 'run_python_tests'), \
                contextlib.redirect_stdout(io.StringIO()):
            result = run_tests.main(['--python-only', '--wire', str(wire), '--output-dir', str(output)])
        self.assertEqual(result, 0)
        summary = json.loads((output / 'summary.json').read_text(encoding='utf-8'))
        self.assertEqual(summary['wire']['status'], 'passed')
        self.assertEqual(len(list((output / 'verified_frames').glob('*.pgm'))), 2)

    def test_output_must_be_new_to_preserve_existing_evidence(self):
        evidence = self.root / 'python_tests.log'
        evidence.write_text('historical evidence', encoding='utf-8')
        with contextlib.redirect_stderr(io.StringIO()):
            result = run_tests.main(['--python-only', '--output-dir', str(self.root)])
        self.assertEqual(result, 1)
        self.assertEqual(evidence.read_text(encoding='utf-8'), 'historical evidence')

    def test_default_output_goes_under_regression_without_touching_old_logs(self):
        historical = self.root / 'build' / 'python_tests.log'
        historical.parent.mkdir()
        historical.write_text('previous run', encoding='utf-8')
        with mock.patch.object(run_tests, 'ROOT', self.root), \
                mock.patch.object(run_tests, 'run_python_tests'), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run_tests.main(['--python-only']), 0)
        summaries = list((self.root / 'build' / 'regression').glob('*/summary.json'))
        self.assertEqual(len(summaries), 1)
        self.assertEqual(historical.read_text(encoding='utf-8'), 'previous run')


if __name__ == '__main__':
    unittest.main()
