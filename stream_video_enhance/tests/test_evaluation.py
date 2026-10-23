"""Independent, literal fixtures for model-gate metrics and publication rules."""
import tempfile
import unittest
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


if __name__ == '__main__':
    unittest.main()
