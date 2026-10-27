"""Real simulator fixtures: catch ignored failures, missing PASS and stuck children."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("core_runner", ROOT / "scripts/run_core_tests.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def fixture(self, body, timeout=60, declarations="", sources=()):
        # Keep real-tool evidence under ignored build/; Windows can retain mapped
        # debug files briefly after every simulator process has already exited.
        regression_dir = ROOT / "build/regression"
        regression_dir.mkdir(parents=True, exist_ok=True)
        path = Path(tempfile.mkdtemp(prefix="runner-fixture-",dir=regression_dir))
        bench = path / "fixture.sv"
        bench.write_text("`timescale 1ns/1ps\nmodule fixture; "+declarations+" initial begin " + body + " end endmodule\n")
        return runner.run_bench([*sources,bench], "fixture", path / "run", timeout=timeout,
                                pass_marker="PASS fixture")

    def test_fixture_bootstraps_missing_regression_parent(self):
        global ROOT
        original_root = ROOT
        with tempfile.TemporaryDirectory(prefix="fresh-core-runner-") as fresh:
            ROOT = Path(fresh) / "checkout"
            try:
                self.assertFalse((ROOT / "build/regression").exists())
                result = self.fixture('$display("PASS fixture"); $finish;')
                self.assertTrue(result["passed"], result)
                self.assertEqual(len(result["stages"]), 3)
                self.assertTrue((ROOT / "build/regression").is_dir())
                self.assertTrue(Path(result["work_dir"]).is_relative_to(ROOT))
            finally:
                ROOT = original_root

    def test_real_pass(self):
        self.assertTrue(self.fixture('$display("PASS fixture"); $finish;')["passed"])

    def test_real_fatal_rejected_even_if_pass_printed(self):
        result = self.fixture('$display("PASS fixture"); $fatal(1,"deliberate failure");')
        self.assertFalse(result["passed"])

    def test_real_missing_pass_rejected(self):
        result = self.fixture('$display("ordinary completion"); $finish;')
        self.assertFalse(result["passed"])
        self.assertEqual(result["reason"], "missing PASS marker")

    def test_real_timeout_rejected(self):
        # Infinite simulated time, real tools, bounded wall time per stage.
        result = self.fixture('forever #1;', timeout=8)
        self.assertFalse(result["passed"])
        self.assertIn("timeout", result["reason"])
        self.assertIsNone(result["stages"][-1]["exit"])
        self.assertEqual(result["stages"][-1]["private_job_active_processes"],0)

    def test_illegal_parameters_rejected(self):
        for module, params in [("token_pipe",".LATENCY(-1)"),
                               ("div25_pipe",".IN_W(22)"),
                               ("div25_pipe",".OUT_W(17)")]:
            with self.subTest(module=module,params=params):
                result=self.fixture('#1; $display("PASS fixture"); $finish;',
                    declarations=f"{module} #({params}) dut();",
                    sources=[ROOT / "rtl" / (module+".sv")])
                self.assertFalse(result["passed"])

    def test_real_compile_error_rejected(self):
        self.assertFalse(self.fixture('not_a_statement ???;')["passed"])


if __name__ == "__main__":
    unittest.main()
