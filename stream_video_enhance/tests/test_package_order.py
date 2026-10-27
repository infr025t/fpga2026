"""Keep the legacy resource comparison compatible with package-typed modules."""
from collections import Counter
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_exchange_tests as exchange


class ExchangePackageOrderTests(unittest.TestCase):
    def test_all_resource_comparison_inputs_are_present_exactly_once(self):
        sources = exchange.exchange_sources(ROOT)
        expected = set((ROOT / 'rtl').glob('*.sv'))
        expected.update((ROOT / 'rtl/experiments').glob('*.sv'))
        expected.add(ROOT / 'sim/tb_resource_exchange.sv')
        self.assertEqual(set(sources), expected)
        self.assertTrue(all(count == 1 for count in Counter(sources).values()))

    def test_package_declarations_precede_all_actual_package_users(self):
        sources = exchange.exchange_sources(ROOT)
        content = {source: source.read_text(encoding='utf-8') for source in sources}
        declarations = {
            name: index for index, source in enumerate(sources)
            for name in re.findall(r'(?m)^\s*package\s+(\w+)\s*;', content[source])
        }
        self.assertIn('core_latency_pkg', declarations)
        self.assertIn('video_runtime_pkg', declarations)
        for index, source in enumerate(sources):
            for name in set(re.findall(r'\b(\w+)\s*::', content[source])):
                with self.subTest(source=source.name, package=name):
                    self.assertIn(name, declarations)
                    self.assertLessEqual(declarations[name], index)


if __name__ == '__main__':
    unittest.main()
