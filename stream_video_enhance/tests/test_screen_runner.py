"""Screen harness failure contracts; mocked children are not RTL evidence."""
from contextlib import ExitStack, redirect_stderr, redirect_stdout
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

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_screen_tests as runner
import run_runtime_tests as simulator


class ScreenRunnerTests(unittest.TestCase):
    def invoke(self, replies, suite='init', arguments=(), existing=False,
               stale_rom=False, real_discovery=False):
        """Exercise main and the shared simulator using controlled child output."""
        folder = tempfile.TemporaryDirectory(prefix='screen-runner-')
        self.addCleanup(folder.cleanup)
        path = Path(folder.name)
        output = path / 'run'
        tools = path / 'Icarus tools'
        tools.mkdir()
        suffix = '.exe' if os.name == 'nt' else ''
        for name in ('iverilog', 'vvp'):
            (tools / (name + suffix)).touch()
        if existing:
            output.mkdir()
            (output / 'keep.txt').write_text('previous evidence', encoding='ascii')
        remaining = {case: list(stages) for case, stages in replies.items()}
        calls = []

        def fake_tool(command, cwd, log, timeout):
            case = Path(cwd).name
            calls.append((case, command, timeout))
            code, timed_out, text = remaining[case].pop(0)
            log.write(text)
            return code, timed_out

        def fake_subprocess(command, cwd, stdout, stderr, timeout):
            code, timed_out = fake_tool(command, cwd, stdout, timeout)
            if timed_out:
                raise subprocess.TimeoutExpired(command, timeout)
            return types.SimpleNamespace(returncode=code)

        cli = ['--output-dir', str(output), '--suite', suite, *arguments]
        if real_discovery:
            cli += ['--iverilog-bin', str(tools)]
        with ExitStack() as stack:
            stack.enter_context(redirect_stdout(io.StringIO()))
            stack.enter_context(redirect_stderr(io.StringIO()))
            stack.enter_context(patch.object(simulator.vivado_runner, '_run_tool', fake_tool))
            stack.enter_context(patch.object(simulator.subprocess, 'run', fake_subprocess))
            if not real_discovery:
                stack.enter_context(patch.object(runner, 'discover', return_value=('iverilog', tools)))
            if stale_rom:
                stale = path / 'stale.sv'
                stale.write_text('module stale; endmodule\n', encoding='ascii')
                stack.enter_context(patch.object(runner.generator, 'ROM', stale))
            code = runner.main(cli)
        summary = json.loads((output / 'summary.json').read_text(encoding='utf-8')) \
            if (output / 'summary.json').is_file() else None
        return code, summary, calls, output, tools

    @staticmethod
    def bus_replies():
        expected = 'unsafe NT35510 timing parameters for 100 MHz'
        return {'bus': [(0, False, ''), (0, False, 'PASS tb_nt35510_bus8 bytes=107\n')],
                **{'reject_' + kind: [(0, False, ''), (1, False, 'FATAL: ' + expected + '\n')]
                   for kind in ('setup', 'low', 'hold', 'gap')}}

    def test_actual_named_pass_binds_source_and_vector_evidence(self):
        code, summary, calls, output, _ = self.invoke(
            {'init': [(0, False, ''), (0, False, 'PASS tb_nt35510_init words=732\n')]})
        self.assertEqual(code, 0)
        self.assertEqual(summary['status'], 'passed')
        self.assertEqual(len(calls), 2)
        self.assertTrue(summary['results'][0]['passed'])
        self.assertTrue(summary['results'][0]['case_passed'])
        saved = json.loads((output / 'init/result.json').read_text(encoding='utf-8'))
        self.assertTrue(saved['passed'])
        self.assertEqual(summary['source_hashes']['rtl/nt35510_bus8.sv'],
                         hashlib.sha256((ROOT / 'rtl/nt35510_bus8.sv').read_bytes()).hexdigest())
        for name, digest in summary['vector_hashes'].items():
            self.assertEqual(digest, hashlib.sha256((output / name).read_bytes()).hexdigest())

    def test_missing_misleading_or_failed_pass_never_completes_the_suite(self):
        for text in ('normal completion\n', 'NOT PASS tb_nt35510_init\n',
                     'PASS tb_nt35510_init\nERROR: deliberate failure\n'):
            with self.subTest(text=text):
                code, summary, _, output, _ = self.invoke(
                    {'init': [(0, False, ''), (0, False, text)]})
                self.assertEqual(code, 1)
                self.assertEqual(summary['status'], 'failed')
                self.assertFalse(summary['results'][0]['case_passed'])
                self.assertTrue((output / 'init/simulate.log').is_file())

    def test_expected_rejection_requires_successful_compile_and_specific_fatal(self):
        code, summary, calls, _, _ = self.invoke(self.bus_replies(), suite='bus')
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 10)
        self.assertEqual(len(summary['results']), 5)
        for result in summary['results'][1:]:
            self.assertFalse(result['passed'])  # The child really failed as requested.
            self.assertTrue(result['accepted_expected_rejection'])
            self.assertTrue(result['case_passed'])

    def test_timeout_compile_failure_and_unrelated_fatal_cannot_pass_negative_case(self):
        expected = 'unsafe NT35510 timing parameters for 100 MHz'
        variants = {
            'compile failure': [(1, False, 'FATAL: ' + expected + '\n')],
            'timeout': [(0, False, ''), (None, True, 'FATAL: ' + expected + '\n')],
            'unrelated fatal': [(0, False, ''), (1, False, 'FATAL: unrelated failure\n')],
            'message without fatal': [(0, False, ''), (1, False, expected + '\n')],
            'zero exit fatal': [(0, False, ''), (0, False, 'FATAL: ' + expected + '\n')],
            'warning plus unrelated fatal': [(0, False, ''),
                (1, False, 'WARNING: ' + expected + '\nFATAL: unrelated failure\n')],
        }
        for name, stages in variants.items():
            with self.subTest(name=name):
                replies = self.bus_replies()
                replies['reject_setup'] = stages
                code, summary, calls, _, _ = self.invoke(replies, suite='bus')
                self.assertEqual(code, 1)
                self.assertEqual(summary['status'], 'failed')
                self.assertEqual(len(summary['results']), 2)
                self.assertFalse(summary['results'][-1]['accepted_expected_rejection'])
                self.assertFalse(summary['results'][-1]['case_passed'])
                self.assertNotIn('reject_low', [case for case, _, _ in calls])

    def test_existing_output_is_preserved_without_launching_a_child(self):
        code, summary, calls, output, _ = self.invoke({}, existing=True)
        self.assertEqual(code, 2)
        self.assertIsNone(summary)
        self.assertFalse(calls)
        self.assertEqual((output / 'keep.txt').read_text(encoding='ascii'), 'previous evidence')
        self.assertEqual([p.name for p in output.iterdir()], ['keep.txt'])

    def test_stale_rom_fails_before_creating_output_or_launching_tools(self):
        code, summary, calls, output, _ = self.invoke({}, stale_rom=True)
        self.assertEqual(code, 2)
        self.assertIsNone(summary)
        self.assertFalse(calls)
        self.assertFalse(output.exists())

    def test_explicit_icarus_directory_reaches_the_child_command(self):
        code, summary, calls, _, tools = self.invoke(
            {'init': [(0, False, ''), (0, False, 'PASS tb_nt35510_init\n')]},
            arguments=['--timeout', '3.5'], real_discovery=True)
        self.assertEqual(code, 0)
        self.assertEqual(summary['simulator'], 'iverilog')
        self.assertEqual(Path(calls[0][1][0]).parent, tools)
        self.assertEqual(Path(calls[1][1][0]).parent, tools)
        self.assertTrue(all(timeout == 3.5 for _, _, timeout in calls))


class ScreenArgumentTests(unittest.TestCase):
    def test_invalid_timeouts_are_rejected_before_tool_discovery(self):
        for value in ('nan', 'inf', '0', '-1', '3601'):
            with self.subTest(value=value), patch.object(runner, 'discover') as discover, \
                 redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as failure:
                runner.main(['--output-dir', 'unused', '--timeout', value])
            self.assertEqual(failure.exception.code, 2)
            discover.assert_not_called()

    def test_conflicting_explicit_tools_cannot_silently_choose_another_backend(self):
        variants = [('--iverilog-bin', 'a', '--vivado-bin', 'b'),
                    ('--simulator', 'vivado', '--iverilog-bin', 'a'),
                    ('--simulator', 'iverilog', '--vivado-bin', 'a')]
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'run'
            for arguments in variants:
                with self.subTest(arguments=arguments), patch.object(runner, 'simulate') as launch, \
                     redirect_stderr(io.StringIO()):
                    self.assertEqual(runner.main(['--output-dir', str(output), *arguments]), 2)
                launch.assert_not_called()
                self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
