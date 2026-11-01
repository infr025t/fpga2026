"""用 Tcl mock 验证 Flash 流程及 ID 错误后恢复；不打开硬件。"""
from pathlib import Path
import tempfile
import tkinter
import unittest

SCRIPT = Path(__file__).with_name("flash_lcd.tcl")


class FlashHelpers(unittest.TestCase):
    def fixture(self, directory, action):
        folder = Path(directory)
        (folder / "lcd_top_snapshot.bit").write_bytes(b"test bit")
        (folder / "lcd_top_snapshot.ltx").write_text("test probes")
        interp = tkinter.Tcl()
        interp.setvar("argv", (action, directory, directory, directory,
                               "mx25l3273f-spi-x1_x2_x4", "210183BCBF83A"))
        interp.eval("""
            set calls {}
            proc write_cfgmem {args} {lappend ::calls [linsert $args 0 write_cfgmem]}
            proc puts {args} {}
        """)
        return interp

    def test_prepare_does_not_connect_hardware(self):
        with tempfile.TemporaryDirectory() as directory:
            interp = self.fixture(directory, "prepare")
            interp.call("source", str(SCRIPT))
            self.assertEqual(int(interp.eval("llength $calls")), 1)
            self.assertEqual(interp.eval("lindex $calls 0 0"), "write_cfgmem")

    def test_id_error_restores_ram_and_closes_connection(self):
        with tempfile.TemporaryDirectory() as directory:
            interp = self.fixture(directory, "program")
            with (Path(directory) / "flash_before.bin").open("wb") as backup:
                backup.truncate(4194304)
            interp.eval("""
                foreach command {open_hw_manager connect_hw_server current_hw_target open_hw_target
                    current_hw_device create_hw_cfgmem set_property create_hw_bitstream
                    program_hw_devices refresh_hw_device close_hw_target disconnect_hw_server close_hw_manager} {
                    proc $command {args} {lappend ::calls [linsert $args 0 [lindex [info level 0] 0]]}
                }
                proc get_hw_targets {args} {return target}
                proc get_hw_devices {args} {return xc7a35t_0}
                proc get_cfgmem_parts {args} {return mx25l3273f-spi-x1_x2_x4}
                proc get_property {args} {return memory}
                proc program_hw_cfgmem {args} {error {JEDEC ID mismatch}}
            """)
            with self.assertRaisesRegex(tkinter.TclError, "JEDEC ID mismatch"):
                interp.call("source", str(SCRIPT))
            self.assertEqual(int(interp.eval("llength [lsearch -all -inline -index 0 $calls program_hw_devices]")), 2)
            self.assertEqual(interp.eval("lindex $calls end 0"), "close_hw_manager")
            self.assertTrue(interp.eval("lsearch -inline -index 1 [lsearch -all -inline -index 0 $calls set_property] PROGRAM.FILE"))


if __name__ == "__main__":
    unittest.main()
