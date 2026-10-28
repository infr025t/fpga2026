"""Factual vendor-profile and generated-ROM integrity; no hardware is accessed."""
from contextlib import redirect_stderr
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import generate_nt35510_rom as generator


class NT35510ProfileTests(unittest.TestCase):
    def test_audited_counts_and_source_identity(self):
        profile, rows = generator.load_profile()
        self.assertEqual(len(rows), 367)
        self.assertEqual(sum(data is not None for _, data in rows), 365)
        self.assertEqual([(index, command) for index, (command, data) in enumerate(rows) if data is None],
                         [(363, 0x1100), (364, 0x2900)])
        self.assertEqual(rows[:5], [(0xf000, 0x55), (0xf001, 0xaa), (0xf002, 0x52), (0xf003, 8), (0xf004, 1)])
        self.assertEqual(rows[-2:], [(0x3600, 0xa3), (0x3a00, 0x55)])
        self.assertEqual(profile['source']['entry_sha256'],
                         '56656bfe4c7d893b932cecce9ed49d4c352e262e3077ec6a1b291f82ef733fdd')
        self.assertFalse(profile['wait_policy']['source_loop_delay_is_milliseconds'])

    def test_committed_rom_is_exactly_generated(self):
        profile, rows = generator.load_profile()
        self.assertEqual(generator.ROM.read_bytes(), generator.render_rom(profile, rows).encode('utf-8'))
        self.assertEqual(generator.main(['--check']), 0)

    def test_independent_word_export_has_correct_rs_order_and_bytes(self):
        profile, rows = generator.load_profile()
        with tempfile.TemporaryDirectory() as folder:
            generator.export_expected(folder, profile, rows)
            data = (Path(folder) / 'expected_init.hex').read_bytes()
            words = [int(line, 16) for line in data.splitlines()]
            manifest = json.loads((Path(folder) / 'expected_init.json').read_text(encoding='utf-8'))
        self.assertEqual(len(words), 732)
        self.assertEqual(words[:4], [0x0f000, 0x10055, 0x0f001, 0x100aa])
        self.assertEqual(words[-6:], [0x01100, 0x02900, 0x03600, 0x100a3, 0x03a00, 0x10055])
        self.assertEqual(manifest['sleep_out_word_index'], 726)
        self.assertEqual(manifest['expected_words_sha256'], hashlib.sha256(data).hexdigest())

    def test_mutated_vendor_value_is_rejected(self):
        profile, _ = generator.load_profile()
        changed = copy.deepcopy(profile)
        changed['entries'][0]['data'] = '0x0054'
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'changed.json'
            path.write_text(json.dumps(changed), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'canonical'):
                generator.load_profile(path)

    def test_hardware_metadata_cannot_disagree_with_the_fixed_rtl(self):
        profile, _ = generator.load_profile()
        mutations = (
            ('bus', 'data_bits', 16),
            ('bus', 'command_word_bits', 8),
            ('bus', 'parameter_word_bits', 8),
            ('bus', 'word_byte_order', 'least-significant byte first'),
            ('bus', 'pixel_format', 'RGB666'),
            ('bus', 'pixel_write_bytes', 3),
            ('orientation', 'width', 480),
            ('orientation', 'height', 800),
            ('orientation', 'madctl', '0x0000'),
            ('orientation', 'pixel_format_register', '0x0066'),
            ('wait_policy', 'clock_hz', 1000),
            ('wait_policy', 'reset_low_ms', 1),
            ('wait_policy', 'reset_release_wait_ms', 1),
            ('wait_policy', 'sleep_out_wait_ms', 5),
            ('wait_policy', 'sleep_out_wait_after_command', '0x2900'),
            ('wait_policy', 'source_loop_delay_is_milliseconds', True),
        )
        for section, name, value in mutations:
            with self.subTest(section=section, name=name), tempfile.TemporaryDirectory() as folder:
                changed = copy.deepcopy(profile)
                changed[section][name] = value
                path = Path(folder) / 'changed.json'
                path.write_text(json.dumps(changed), encoding='utf-8')
                # Both CLI checking and the shared loader used by the screen
                # runner must reject metadata drift before any tool is launched.
                with self.assertRaisesRegex(ValueError, section + r'\.' + name):
                    generator.load_profile(path)
                with redirect_stderr(io.StringIO()):
                    self.assertEqual(generator.main(['--check', '--profile', str(path)]), 1)

    def test_canonical_source_identity_cannot_be_replaced_by_another_valid_hash(self):
        profile, _ = generator.load_profile()
        for name in ('archive_sha256', 'entry_sha256'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                changed = copy.deepcopy(profile)
                changed['source'][name] = '0' * 64
                path = Path(folder) / 'changed.json'
                path.write_text(json.dumps(changed), encoding='utf-8')
                with self.assertRaisesRegex(ValueError, r'source\.' + name):
                    generator.load_profile(path)

    def test_missing_contract_sections_and_wrong_json_types_fail_cleanly(self):
        profile, _ = generator.load_profile()
        changed = copy.deepcopy(profile)
        changed['wait_policy']['source_loop_delay_is_milliseconds'] = 0
        boolean_schema = copy.deepcopy(profile)
        boolean_schema['schema_version'] = True
        bad_entry = copy.deepcopy(profile)
        bad_entry['entries'][0] = None
        variants = [None, [], changed, boolean_schema, bad_entry]
        for section in ('bus', 'orientation', 'wait_policy', 'source'):
            changed = copy.deepcopy(profile)
            del changed[section]
            variants.append(changed)
        for changed in variants:
            with self.subTest(value=changed if not isinstance(changed, dict) else list(changed)), \
                    tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'changed.json'
                path.write_text(json.dumps(changed), encoding='utf-8')
                with self.assertRaises(ValueError):
                    generator.load_profile(path)
                with redirect_stderr(io.StringIO()):
                    self.assertEqual(generator.main(['--check', '--profile', str(path)]), 1)

    def test_wrong_counts_indices_and_width_are_rejected(self):
        profile, _ = generator.load_profile()
        for mutation in ('count', 'index', 'width'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as folder:
                changed = copy.deepcopy(profile)
                if mutation == 'count':changed['counts']['word_transfers'] = 731
                elif mutation == 'index':changed['entries'][1]['index'] = 0
                else:changed['entries'][0]['command'] = '0x1F000'
                path = Path(folder) / 'changed.json'
                path.write_text(json.dumps(changed), encoding='utf-8')
                with self.assertRaises(ValueError):generator.load_profile(path)

    def test_stale_rom_check_fails_and_expected_evidence_is_not_overwritten(self):
        profile, rows = generator.load_profile()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            stale = root / 'stale.sv';stale.write_text('module stale; endmodule\n', encoding='ascii')
            with redirect_stderr(io.StringIO()):
                self.assertEqual(generator.main(['--check', '--output', str(stale)]), 1)
            expected = root / 'expected';expected.mkdir()
            path = expected / 'expected_init.hex';path.write_text('old evidence\n', encoding='ascii')
            with self.assertRaisesRegex(ValueError, 'overwrite'):
                generator.export_expected(expected, profile, rows)
            self.assertEqual(path.read_text(encoding='ascii'), 'old evidence\n')


if __name__ == '__main__':
    unittest.main()
