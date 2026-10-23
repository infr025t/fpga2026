"""Tcl syntax/guard dry runs with mocked Vivado commands, never synthesis."""
from pathlib import Path
import tempfile
import unittest
try:
    import tkinter
except ImportError:
    tkinter = None


@unittest.skipIf(tkinter is None, 'Tcl interpreter is unavailable')
class VisionBuildTests(unittest.TestCase):
    def dry_run(self, bram36=40, bram18=6, dsp=24, lut=8000, bram_limit=45):
        interpreter = tkinter.Tcl()
        calls = []
        script = Path(__file__).with_name('synth_vision.tcl')
        def record(name):
            def callback(*args):
                calls.append((name, args))
                return ''
            return callback
        for name in ('create_project', 'read_verilog', 'synth_design', 'report_utilization',
                     'report_timing_summary', 'write_checkpoint', 'create_clock', 'set_false_path', 'puts'):
            interpreter.createcommand(name, record(name))
        interpreter.createcommand('get_ports', lambda *args: args[-1])
        def read_xdc(path):
            calls.append(('read_xdc', (path,)))
            interpreter.call('source', path)
            return ''
        interpreter.createcommand('read_xdc', read_xdc)
        def cells(*args):
            expression = args[-1]
            count = bram36 if 'RAMB36' in expression else bram18 if 'RAMB18' in expression else dsp if 'DSP48' in expression else lut
            return tuple(f'cell_{index}' for index in range(count))
        interpreter.createcommand('get_cells', cells)
        with tempfile.TemporaryDirectory() as d:
            interpreter.setvar('env(VISION_BUILD_DIR)', d)
            interpreter.setvar('vision_bram_limit', bram_limit)
            error = None
            try:
                interpreter.call('source', str(script.resolve()))
            except tkinter.TclError as exc:
                error = str(exc)
        return calls, error

    def test_ooc_synthesis_and_clock_constraints_pass_under_budget(self):
        calls, error = self.dry_run()
        self.assertIsNone(error)
        synth = next(args for name, args in calls if name == 'synth_design')
        self.assertIn('vision_top', synth)
        self.assertIn('out_of_context', synth)
        self.assertTrue(any(name == 'create_clock' for name, _ in calls))
        self.assertTrue(any(name == 'write_checkpoint' for name, _ in calls))

    def test_half_block_resource_overflow_stops_before_checkpoint(self):
        calls, error = self.dry_run(bram36=44, bram18=3)
        self.assertIn('exceeds budget', error)
        self.assertFalse(any(name == 'write_checkpoint' for name, _ in calls))

    def test_budget_cannot_exceed_board_capacity(self):
        calls, error = self.dry_run(bram_limit=51)
        self.assertIn('Invalid vision resource budget', error)
        self.assertFalse(any(name == 'synth_design' for name, _ in calls))


if __name__ == '__main__':
    unittest.main()
