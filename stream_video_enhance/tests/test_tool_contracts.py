"""Tool-independent regression gates for simulator and synthesis evidence."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_core_tests as simulator
import run_core_synth as synthesis


class SimulatorContractTests(unittest.TestCase):
    def test_marker_is_a_line_not_a_substring_or_tcl_echo(self):
        for output in ('NOT PASS fixture\n', 'FAIL expected PASS fixture\n',
                       '# puts "PASS fixture"\n', 'PASS fixture_extra\n'):
            with self.subTest(output=output):
                self.assertFalse(simulator.has_pass_marker(output, 'PASS fixture'))
        self.assertTrue(simulator.has_pass_marker('PASS fixture\n', 'PASS fixture'))
        self.assertTrue(simulator.has_pass_marker('PASS fixture frames=2 pixels=128\n', 'PASS fixture'))

    def test_simulator_result_rejects_a_misleading_marker(self):
        def fake_tool(command, cwd, log, timeout):
            log.write('NOT PASS fixture\n')
            return 0, False
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(simulator, 'missing_simulator_tools', return_value=[]), \
                 patch.object(simulator, '_run_tool', fake_tool):
                result = simulator.run_bench([], 'fixture', folder)
            self.assertFalse(result['passed'])
            self.assertEqual(result['reason'], 'missing PASS marker')

    def test_missing_tool_is_explicit_and_preserves_failed_result(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(simulator, 'BIN', Path(folder) / 'uninstalled'), \
                 patch.object(simulator, '_run_tool') as launch:
                result = simulator.run_bench([], 'fixture', Path(folder) / 'work')
            launch.assert_not_called()
            self.assertFalse(result['passed'])
            self.assertIn('Set VIVADO_BIN', result['reason'])
            self.assertEqual(result['stages'], [])
            saved = json.loads((Path(folder) / 'work/result.json').read_text(encoding='utf-8'))
            self.assertEqual(saved, result)


class SimulationSourceContractTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.sources = {}
        for name in synthesis.REQUIRED_SIMULATION_SOURCES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode('ascii'))
            self.sources[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.manifest = {
            'results': [{'top': top, 'passed': True}
                        for top in sorted(synthesis.REQUIRED_SIMULATION_TOPS)],
            'source_hashes': self.sources,
        }

    def test_complete_source_binding_passes(self):
        checked = synthesis.verify_simulation_sources(self.manifest, self.root)
        self.assertEqual(set(checked), synthesis.REQUIRED_SIMULATION_SOURCES)

    def test_non_object_manifest_is_rejected(self):
        for manifest in (None, [], 'not an object'):
            with self.subTest(manifest=manifest), self.assertRaisesRegex(ValueError, 'JSON object'):
                synthesis.verify_simulation_sources(manifest, self.root)

    def test_same_latency_does_not_accept_changed_rtl(self):
        (self.root / 'rtl/detail_enhance.sv').write_bytes(b'changed computation')
        with self.assertRaisesRegex(ValueError, 'source changed.*detail_enhance'):
            synthesis.verify_simulation_sources(self.manifest, self.root)

    def test_changed_numerical_vector_generator_is_rejected(self):
        (self.root / 'scripts/core_vectors.py').write_bytes(b'changed numerical oracle')
        with self.assertRaisesRegex(ValueError, 'source changed.*core_vectors'):
            synthesis.verify_simulation_sources(self.manifest, self.root)

    def test_stage_only_results_cannot_claim_complete_core_regression(self):
        self.manifest['results'] = [{'top': 'tb_core_stages', 'passed': True}]
        with self.assertRaisesRegex(ValueError, 'missing core regression cases'):
            synthesis.verify_simulation_sources(self.manifest, self.root)

    def test_each_vga_case_is_required(self):
        for missing in ('tb_guided_core_vga', 'tb_guided_core_vga_align'):
            with self.subTest(missing=missing):
                manifest = copy.deepcopy(self.manifest)
                manifest['results'] = [result for result in manifest['results']
                                       if result['top'] != missing]
                with self.assertRaisesRegex(ValueError, 'missing core regression cases.*' + missing):
                    synthesis.verify_simulation_sources(manifest, self.root)

    def test_original_complete_manifest_still_binds_without_inventing_model_hashes(self):
        manifest = json.loads((ROOT / 'reports/rtl/core_timing_fix_results.json').read_text())
        self.assertNotIn('model/reference.py', manifest['source_hashes'])
        checked = synthesis.verify_simulation_sources(manifest, ROOT)
        self.assertEqual(set(checked), synthesis.REQUIRED_SIMULATION_SOURCES)

    def test_incomplete_source_inventory_is_rejected(self):
        del self.sources['sim/tb_guided_core.sv']
        with self.assertRaisesRegex(ValueError, 'missing core sources'):
            synthesis.verify_simulation_sources(self.manifest, self.root)

    def test_failed_or_absent_simulation_results_are_rejected(self):
        for results in ([], [{'passed': False}], [{'passed': True}, {'passed': False}]):
            with self.subTest(results=results):
                manifest = copy.deepcopy(self.manifest)
                manifest['results'] = results
                with self.assertRaisesRegex(ValueError, 'only passing results'):
                    synthesis.verify_simulation_sources(manifest, self.root)

    def test_recorded_model_oracle_is_also_bound(self):
        self.sources['model/reference.py'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'source is missing.*reference'):
            synthesis.verify_simulation_sources(self.manifest, self.root)

    def test_tooling_only_changes_do_not_invalidate_numeric_simulation(self):
        self.sources['scripts/run_core_tests.py'] = '0' * 64
        self.assertEqual(set(synthesis.verify_simulation_sources(self.manifest, self.root)),
                         synthesis.REQUIRED_SIMULATION_SOURCES)

    def test_parent_paths_are_rejected(self):
        self.sources['../outside.sv'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'invalid simulation source path'):
            synthesis.verify_simulation_sources(self.manifest, self.root)


if __name__ == '__main__':
    unittest.main()
