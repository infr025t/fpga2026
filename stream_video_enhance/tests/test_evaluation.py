"""Independent, literal fixtures for model-gate metrics and publication rules."""
import tempfile
import unittest
import json
import subprocess
from unittest.mock import patch
from pathlib import Path
import numpy as np
try:
    from stream_video_enhance.model import evaluate as ev
    from stream_video_enhance.model import dataset as ds
except ImportError:
    ev = ds = None


class EvaluationTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(ev, 'Quality evaluation API has not been implemented')
        self.assertIsNotNone(ds, 'Registered dataset API has not been implemented')

    def test_psnr_uses_float_mse(self):
        self.assertAlmostEqual(ev.psnr(np.array([[0, 4]], np.uint8),
                                       np.array([[2, 2]], np.uint8)),
                               10 * np.log10(255**2 / 4))
        self.assertEqual(ev.psnr(np.zeros((1, 1)), np.zeros((1, 1))), float('inf'))

    def test_contrast_is_difference_of_mask_means(self):
        x = np.array([[10, 30, 90, 110]])
        self.assertEqual(ev.contrast(x, x < 50, x > 50), 80)
        with self.assertRaises(ValueError):
            ev.contrast(x, x < 0, x > 50)

    def test_new_clipping_excludes_existing_saturation_from_numerator_only(self):
        raw = np.array([[0, 1, 254, 255]], np.uint8)
        out = np.array([[0, 0, 255, 255]], np.uint8)
        self.assertEqual(ev.new_clipping(raw, out, np.ones_like(raw, bool)), .5)

    def test_temporal_noise_is_pixelwise_population_std_then_spatial_mean(self):
        frames = np.array([[[0, 100]], [[2, 100]]])
        self.assertEqual(ev.temporal_noise(frames, np.array([[True, True]])), .5)

    def test_failure_or_missing_forbids_profile_publication(self):
        self.assertEqual(ev.aggregate_status({'a': {'status': 'PASS'}}), 'PASS')
        for status in ('FAIL', 'MISSING'):
            checks = {'a': {'status': 'PASS'}, 'b': {'status': status}}
            self.assertNotEqual(ev.aggregate_status(checks), 'PASS')
            with tempfile.TemporaryDirectory() as p:
                self.assertFalse(ev.publish_profile(Path(p), checks, {'epsilon': 64}))
                self.assertFalse((Path(p) / 'profile.json').exists())

    def test_unrecognized_or_empty_required_checks_cannot_pass(self):
        self.assertEqual(ev.aggregate_status({}), 'MISSING')
        self.assertEqual(ev.aggregate_status({'a': {'status': 'DEFERRED'}}), 'MISSING')
        self.assertEqual(ev.aggregate_status({'a': {'status': 'PASS'},
                                            'rtl': {'status': 'DEFERRED', 'required': False}}), 'PASS')

    def test_saved_step_profiles_cross_each_edge_in_all_four_modes(self):
        # Independent literal plateaus: horizontal image intensity changes only
        # between rows. A middle-row trace cannot contain both endpoints.
        vertical = np.array([[32]*16 + [224]*16]*24, dtype=np.uint8)
        horizontal = np.array([[32]*32]*12 + [[224]*32]*12, dtype=np.uint8)
        diagonal = np.array([[32 if x < y+4 else 224 for x in range(32)]
                             for y in range(24)], dtype=np.uint8)
        arrays = {'holdout_step_'+direction+'_clean': image for direction, image in
                  [('vertical', vertical), ('horizontal', horizontal), ('diagonal', diagonal)]}
        registration = {'primary_enhancement': {'holdout': []}, 'cases': []}
        result = {'selected_candidate': {'config': {'epsilon': 64, 'T_D': 2, 'T_E': 2, 'G_E': 384}},
                  'holdout': {'cases': [dict(id='absent', category=category,
                                            modes={'ENHANCE': {'contrast_vs_raw': 1}})
                                        for category in ('line', 'text', 'texture')]}}
        with tempfile.TemporaryDirectory() as folder:
            ev._visuals(Path(folder), registration, arrays, result)
            profiles = json.loads((Path(folder)/'edge_profiles.json').read_text())
            for direction in ('vertical', 'horizontal', 'diagonal'):
                for mode in ('RAW', 'BASE', 'DENOISE', 'ENHANCE'):
                    with self.subTest(direction=direction, mode=mode):
                        self.assertEqual(profiles[direction][mode][0], 32)
                        self.assertEqual(profiles[direction][mode][-1], 224)

    def test_registration_required_and_tampered_archive_rejected(self):
        with tempfile.TemporaryDirectory() as p:
            root = Path(p)
            with self.assertRaises(FileNotFoundError):
                ds.load_registration(root)
            ds.register(root, include_sources=False)
            registration, arrays = ds.load_registration(root)
            self.assertEqual(len(registration['primary_enhancement']['holdout']), 2)
            self.assertEqual(arrays['holdout_temporal_noise'].shape[0], 64)
            archive = root / 'inputs.npz'
            archive.write_bytes(archive.read_bytes() + b'tamper')
            with self.assertRaises(ValueError):
                ds.load_registration(root)

    def test_noise_has_literal_nonnegative_ties_away_rounding(self):
        np.testing.assert_array_equal(ds.gray_round(np.array([-.5, .5, 1.5, 254.5, 255.5])),
                                      [0, 1, 2, 255, 255])

    def test_registration_is_immutable_and_splits_have_distinct_bytes(self):
        with tempfile.TemporaryDirectory() as p:
            ds.register(Path(p), include_sources=False)
            with self.assertRaises(FileExistsError):
                ds.register(Path(p), include_sources=False)
            registration, arrays = ds.load_registration(Path(p))
            a, b = registration['primary_enhancement'].values()
            self.assertFalse(np.array_equal(arrays[a[0]], arrays[b[0]]))

    def test_expanded_registration_has_72_registered_candidates_and_policy(self):
        with tempfile.TemporaryDirectory() as p:
            reg = ds.register(Path(p), include_sources=False, experiment='expanded-v2')
            configs = list(ev.registered_candidates(reg))
            self.assertEqual(len(configs), 72)
            self.assertEqual({c['epsilon'] for c in configs}, {16, 64, 256, 1024})
            self.assertEqual({c['G_E'] for c in configs}, {384, 448, 512})
            self.assertEqual(configs[0], dict(epsilon=16, T_D=2, T_E=2, G_E=384, L=16))
            self.assertEqual(configs[-1], dict(epsilon=1024, T_D=8, T_E=4, G_E=512, L=16))
            self.assertFalse(reg['evidence_policy']['real_exposure_classes']['required'])
            self.assertEqual(reg['evidence_policy']['real_exposure_classes']['status'], 'DEFERRED')
            self.assertIn('real_image_classes', reg['required_checks'])

    def test_expanded_primaries_and_random_streams_are_independent_of_round1(self):
        original, old = ds.load_registration(ds.DEFAULT_REPORT)
        with tempfile.TemporaryDirectory() as p:
            ds.register(Path(p), include_sources=False, experiment='expanded-v2')
            reg, arrays = ds.load_registration(Path(p))
            self.assertIn('2026102302', reg['split_seed_entropy'])
            for key in reg['primary_enhancement']['holdout']:
                for old_key, value in old.items():
                    if value.ndim == 2 and value.dtype == np.uint8:
                        self.assertFalse(np.array_equal(arrays[key], value), (key, old_key))
                for tuning_key, value in arrays.items():
                    if tuning_key.startswith('tuning_') and value.ndim==2 and value.dtype==np.uint8:
                        self.assertFalse(np.array_equal(arrays[key], value), (key, tuning_key))
                for suffix in ('_fg', '_bg'):
                    self.assertTrue(arrays[key.removesuffix('_clean')+suffix][4:-4,4:-4].any())
            for split in ('tuning', 'holdout'):
                for key in (split+'_flat_s8_n0', split+'_temporal_noise'):
                    self.assertFalse(np.array_equal(arrays[key], old[key]))
            self.assertFalse(np.array_equal(arrays['tuning_temporal_noise'], arrays['holdout_temporal_noise']))
            self.assertEqual(reg['fixture_policy']['canonical_stress'], 'REUSED_NOT_NOVEL_HOLDOUT_EVIDENCE')

    def test_candidate_iterator_consumes_registration_not_builtin_grid(self):
        reg = {'candidates': dict(epsilon=[1024], denoise_threshold=[8],
                                 enhance_threshold=[4], enhance_gain=[512], limit=16)}
        self.assertEqual(list(ev.registered_candidates(reg)),
                         [dict(epsilon=1024, T_D=8, T_E=4, G_E=512, L=16)])

    def test_required_inventory_cannot_be_omitted_or_unknown_at_publication(self):
        for status in ('FAIL', 'MISSING', 'DEFERRED', 'unknown'):
            with tempfile.TemporaryDirectory() as p:
                self.assertFalse(ev.publish_profile(p, {'a': {'status': status}}, {}, required_checks=['a']))
        with tempfile.TemporaryDirectory() as p:
            self.assertFalse(ev.publish_profile(p, {'a': {'status': 'PASS'}}, {}, required_checks=['a','b']))
            self.assertFalse((Path(p)/'profile.json').exists())

    def test_three_same_class_photos_do_not_cover_real_image_classes(self):
        arrays = {f'image{i}': np.full((16,16), 128, np.uint8) for i in range(3)}
        arrays['fg'] = np.indices((16,16))[1] < 8
        arrays['bg'] = ~arrays['fg']
        cases = [dict(id=f'image{i}', category='real', region_class='text',
                      foreground='fg', background='bg') for i in range(3)]
        check = ev.real_image_class_check({'cases':cases}, arrays)
        self.assertEqual(check['status'], 'MISSING')
        self.assertEqual(check['classes_present'], ['text'])
        cases[0]['region_class'], cases[1]['region_class'] = 'flat', 'texture'
        self.assertEqual(ev.real_image_class_check({'cases':cases}, arrays)['status'], 'PASS')
        arrays['fg'][:] = False
        self.assertEqual(ev.real_image_class_check({'cases':cases}, arrays)['status'], 'MISSING')

    def test_missing_status_cannot_publish_a_profile(self):
        with tempfile.TemporaryDirectory() as p:
            self.assertFalse(ev.publish_profile(p, {'a': {}}, {}, required_checks=['a']))

    def test_expanded_policy_cannot_silently_drop_required_checks(self):
        with tempfile.TemporaryDirectory() as p:
            root = Path(p)
            reg = ds.register(root, include_sources=False, experiment='expanded-v2')
            reg['required_checks'].remove('real_image_classes')
            (root/'registration.json').write_text(json.dumps(reg))
            with self.assertRaisesRegex(ValueError, 'required'):
                ds.load_registration(root)

    def test_expanded_primary_contract_cannot_be_weakened_with_matching_inventory(self):
        root = ds.DEFAULT_REPORT.parent/'model_gate_round2'
        original = json.loads((root/'registration.json').read_text(encoding='utf-8'))
        for split in ('tuning','holdout'):
            targets = original['primary_enhancement'][split]
            for replacement in ([], targets[:1], [targets[0],targets[0]], list(reversed(targets)),
                                [split+'_line_vertical_1_clean',targets[1]]):
                reg = json.loads(json.dumps(original))
                reg['primary_enhancement'][split] = replacement
                reg['required_checks'] = [k for k in reg['required_checks'] if not k.startswith('primary_holdout_')]
                reg['required_checks'] += ['primary_'+k for k in reg['primary_enhancement']['holdout']]
                with self.subTest(split=split, replacement=replacement):
                    with patch.object(Path,'read_text',return_value=json.dumps(reg)):
                        with self.assertRaisesRegex(ValueError, 'primary'):
                            ds.load_registration(root)

    def test_expanded_primary_case_must_match_frozen_split_class_and_clean_id(self):
        root = ds.DEFAULT_REPORT.parent/'model_gate_round2'
        original = json.loads((root/'registration.json').read_text(encoding='utf-8'))
        for mutation in ('absent','duplicate','split','category','clean','sigma'):
            reg = json.loads(json.dumps(original))
            case = next(c for c in reg['cases'] if c['id']=='holdout_text_low_clean')
            if mutation=='absent': reg['cases'].remove(case)
            elif mutation=='duplicate': reg['cases'].append(dict(case))
            else: case[mutation] = dict(split='tuning',category='line',clean='holdout_flat_clean',sigma=8)[mutation]
            with self.subTest(mutation=mutation):
                with patch.object(Path,'read_text',return_value=json.dumps(reg)):
                    with self.assertRaisesRegex(ValueError, 'primary'):
                        ds.load_registration(root)

    def _execution_repo(self, root):
        # Real local Git fixture; source contents and mutations are independent
        # of the production evaluator, and no official corpus is modified.
        paths = ['model/__init__.py','model/dataset.py','model/evaluate.py','model/reference.py',
                 'tests/test_reference.py','tests/test_evaluation.py']
        for suffix in paths:
            p = root/'stream_video_enhance'/suffix
            p.parent.mkdir(parents=True,exist_ok=True)
            p.write_text('# committed fixture '+suffix+'\n')
        for command in (['init','--quiet'], ['config','user.name','Gate Test'],
                        ['config','user.email','gate-test@example.invalid'], ['config','core.autocrlf','false'], ['add','.'],
                        ['commit','--quiet','-m','committed execution fixture']):
            subprocess.run(['git',*command],cwd=root,capture_output=True,check=True)

    def test_execution_sources_must_be_committed_and_match_before_search(self):
        for mutation in ('dirty','staged','untracked','missing'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as p:
                root = Path(p); self._execution_repo(root)
                source = root/'stream_video_enhance/model/reference.py'
                if mutation=='untracked': (source.parent/'extra.py').write_text('# untracked execution source\n')
                elif mutation=='missing': source.unlink()
                else:
                    source.write_text('# uncommitted arithmetic\n')
                    if mutation=='staged': subprocess.run(['git','add','.'],cwd=root,check=True,capture_output=True)
                with self.assertRaisesRegex(ValueError,'execution source'):
                    ev.capture_execution_sources(root)

    def test_execution_provenance_keeps_entry_commit_across_documentation_head_change(self):
        with tempfile.TemporaryDirectory() as p:
            root=Path(p); self._execution_repo(root)
            bundle=ev.capture_execution_sources(root)
            entry=bundle['commit']
            self.assertEqual(len(bundle['source_sha256']),6)
            for name, digest in bundle['source_sha256'].items():
                committed=subprocess.check_output(['git','show',entry+':'+name],cwd=root)
                self.assertEqual(digest,ds.sha(committed))
            (root/'README.md').write_text('documentation only\n')
            subprocess.run(['git','add','README.md'],cwd=root,check=True,capture_output=True)
            subprocess.run(['git','commit','--quiet','-m','docs only'],cwd=root,check=True,capture_output=True)
            self.assertNotEqual(subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),entry)
            ev.verify_execution_sources(bundle,root)
            self.assertEqual(bundle['commit'],entry)

    def test_execution_source_changes_during_run_prevent_publication(self):
        for mutation in ('modified','untracked','committed'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as p:
                root=Path(p); self._execution_repo(root)
                bundle=ev.capture_execution_sources(root)
                name='extra.py' if mutation=='untracked' else 'reference.py'
                (root/'stream_video_enhance/model'/name).write_text('# changed during evaluation\n')
                if mutation=='committed':
                    subprocess.run(['git','add','.'],cwd=root,check=True,capture_output=True)
                    subprocess.run(['git','commit','--quiet','-m','changed source'],cwd=root,check=True,capture_output=True)
                with self.assertRaisesRegex(ValueError,'execution source'):
                    ev.verify_execution_sources(bundle,root)


if __name__ == '__main__':
    unittest.main()
