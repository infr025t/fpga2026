"""离线验证 Tcl 解析、诊断选项和分片 VIO 读数；不会连接硬件。"""
from pathlib import Path
import tempfile
import tkinter
import unittest

SCRIPTS = Path(__file__).resolve().parent


class HardwareHelpers(unittest.TestCase):
    def test_tcl_scripts_are_complete(self):
        interp = tkinter.Tcl()
        for path in SCRIPTS.glob("*.tcl"):
            self.assertTrue(int(interp.call("info", "complete", path.read_text(encoding="utf-8"))), path.name)

    def test_options_and_split_probes(self):
        interp = tkinter.Tcl()
        with tempfile.TemporaryDirectory(prefix="lcd artifacts ") as directory:
            artifact = Path(directory) / "lcd_top_snapshot.ltx"
            artifact.write_text("fixture", encoding="utf-8")
            interp.setvar("argv", ("inspect", "-snapshot", "-artifact-dir", directory))
            interp.call("source", str(SCRIPTS / "hardware_common.tcl"))
            self.assertEqual(interp.eval("lindex $argv 0"), "inspect")
            self.assertEqual(int(interp.getvar("snapshot_mode")), 1)
            self.assertEqual(Path(str(interp.call("require_artifact", artifact.name))), artifact)
            interp.eval("""
                proc get_hw_probes {args} {return {low high}}
                proc set_property {args} {}
                proc get_property {name probe} {
                    if {$name eq {PROBE_PORT_BITS}} {
                        return [expr {$probe eq {low} ? {[7:0]} : {[15:8]}}]
                    }
                    return [expr {$probe eq {low} ? {34} : {12}}]
                }
                set vio mock
            """)
            self.assertEqual(int(interp.call("value", 0)), 0x1234)

    def test_missing_artifact_directory_value(self):
        interp = tkinter.Tcl()
        interp.setvar("argv", ("inspect", "-artifact-dir"))
        with self.assertRaisesRegex(tkinter.TclError, "requires a path"):
            interp.call("source", str(SCRIPTS / "hardware_common.tcl"))

    def test_pause_rejects_wrong_mode_or_nonpositive_rounds_before_hardware(self):
        for mode, rounds in (("0", "10"), ("1", "10"), ("2", "0"), ("2", "-1"), ("2", "bad")):
            with self.subTest(mode=mode, rounds=rounds):
                interp = tkinter.Tcl()
                interp.setvar("argv", ("offline_pause_validation", mode, rounds))
                interp.eval("set hardware_calls 0; proc open_hw_manager {} {incr ::hardware_calls; error HARDWARE_CALLED}")
                with self.assertRaisesRegex(tkinter.TclError, "Pause stability requires|Expected positive pause round count"):
                    interp.call("source", str(SCRIPTS / "pause_stability.tcl"))
                self.assertEqual(int(interp.getvar("hardware_calls")), 0)

    def test_pause_default_is_ten_rounds(self):
        interp = tkinter.Tcl()
        interp.setvar("argv", ("offline_pause_default", "2"))
        interp.eval("""
            rename file real_file
            proc file {command args} {
                if {$command eq {mkdir}} {return}
                return [real_file $command {*}$args]
            }
            proc open_hw_manager {} {error STOP_BEFORE_HARDWARE}
        """)
        with self.assertRaisesRegex(tkinter.TclError, "STOP_BEFORE_HARDWARE"):
            interp.call("source", str(SCRIPTS / "pause_stability.tcl"))
        self.assertEqual(int(interp.getvar("max_records")), 10)

    def test_program_explicit_lite_variant_uses_matching_probes(self):
        with tempfile.TemporaryDirectory() as directory:
            for extension in ("bit", "ltx"):
                (Path(directory) / ("lcd_top." + extension)).write_text("fixture")
            interp = tkinter.Tcl()
            interp.setvar("argv", ("program", "lcd_top", "-artifact-dir", directory))
            interp.eval("""
                set programmed 0
                foreach command {open_hw_manager connect_hw_server current_hw_target open_hw_target
                    current_hw_device set_property close_hw_target disconnect_hw_server close_hw_manager} {
                    proc $command {args} {}
                }
                proc get_hw_targets {args} {return target}
                proc get_hw_devices {args} {return device}
                proc program_hw_devices {args} {incr ::programmed; error STOP_AFTER_MOCK_PROGRAM}
            """)
            with self.assertRaisesRegex(tkinter.TclError, "STOP_AFTER_MOCK_PROGRAM"):
                interp.call("source", str(SCRIPTS / "paired_overview_hardware.tcl"))
            self.assertEqual(int(interp.getvar("programmed")), 1)


if __name__ == "__main__":
    unittest.main()
