"""检查入口拒绝错误参数，避免实际测试对象与请求不一致。"""
from pathlib import Path
import subprocess
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]


class RunnerArguments(unittest.TestCase):
    def test_vga_rejects_nonparametric_bench(self):
        label = "runner_reject_" + uuid.uuid4().hex
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/run_lcd_tests.py"),
             label, "tb_statistics", "--vga"],
            capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("--vga supports only tb_video_path", result.stderr)
        self.assertFalse((ROOT / "reports" / label).exists())


if __name__ == "__main__":
    unittest.main()
