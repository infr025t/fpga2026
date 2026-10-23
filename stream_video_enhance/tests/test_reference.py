"""Numerical gate: independent Python-int/float loops are the small-image oracle."""
import importlib
import itertools
import unittest

import numpy as np


EPSILONS = (16, 64, 256, 1024)
MODES = ("RAW", "BASE", "DENOISE", "ENHANCE")


def oracle(image, epsilon, y, x):
    """One final pixel, using 25 separate 25-point loops and Python scalars."""
    coeffs = []
    for cy in range(y - 2, y + 3):
        for cx in range(x - 2, x + 3):
            p = [int(image[j, i]) for j in range(cy - 2, cy + 3)
                 for i in range(cx - 2, cx + 3)]
            s1, s2 = sum(p), sum(v * v for v in p)
            v = 25 * s2 - s1 * s1
            den = v + 625 * epsilon
            a = (4096 * v + den // 2) // den
            m = (256 * s1 + 12) // 25
            b = ((4096 - a) * m + 2048) // 4096
            af = v / den
            coeffs.append((a, b, af, (1.0 - af) * s1 / 25))
    abar = (sum(c[0] for c in coeffs) + 12) // 25
    bbar = (sum(c[1] for c in coeffs) + 12) // 25
    raw = int(image[y, x])
    b8 = min(max((abar * raw + 8) // 16 + bbar, 0), 65280)
    bf = sum(c[2] for c in coeffs) * raw / 25 + sum(c[3] for c in coeffs) / 25
    return b8, bf


class ReferenceTests(unittest.TestCase):
    def setUp(self):
        try:
            self.ref = importlib.import_module("stream_video_enhance.model.reference")
        except ModuleNotFoundError:
            self.fail("Task 1 numerical reference API has not been implemented")

    def test_crop_and_original_center_not_window_corner(self):
        image = np.arange(17 * 19, dtype=np.int64).reshape(17, 19).astype(np.uint8)
        for mode in MODES:
            for fn in (self.ref.filter_fixed, self.ref.filter_float):
                result = fn(image, 64, 4, 256, mode)
                self.assertEqual(result.shape, (9, 11))
                self.assertEqual(result.dtype, np.uint8)
                if mode == "RAW":
                    np.testing.assert_array_equal(result, image[4:-4, 4:-4])

    def test_independent_brute_force_small_images_and_checkpoints(self):
        rng = np.random.default_rng(104)
        for shape in ((16, 16), (17, 19)):
            image = rng.integers(0, 256, shape, dtype=np.uint8)
            for eps in EPSILONS:
                layers = self.ref.fixed_layers(image, eps)
                bf = self.ref.filter_float(image, eps, 0, 0, "BASE")
                for y, x in ((4, 4), (shape[0] // 2, shape[1] // 2),
                             (shape[0] - 5, shape[1] - 5)):
                    b8, expected_float = oracle(image, eps, y, x)
                    self.assertEqual(int(layers["base_q8"][y - 4, x - 4]), b8)
                    self.assertEqual(int(bf[y - 4, x - 4]), int(np.floor(expected_float + 0.5)))
                    p = [int(image[j, i]) for j in range(y - 2, y + 3)
                         for i in range(x - 2, x + 3)]
                    s1, s2 = sum(p), sum(t*t for t in p)
                    self.assertEqual(int(layers["s1"][y - 2, x - 2]), s1)
                    self.assertEqual(int(layers["s2"][y - 2, x - 2]), s2)
                    self.assertEqual(int(layers["variance_numerator"][y - 2, x - 2]), 25*s2-s1*s1)

    def test_div25_exhaustive_unrounded_and_correction(self):
        n = np.arange(1_632_013, dtype=np.int64)
        result = self.ref.div25_exact(n)
        np.testing.assert_array_equal(result, n // 25)
        # The specified correction is conservative: over this legal domain
        # q0 never overestimates. Do not fabricate an unreachable correction.
        np.testing.assert_array_equal(n * 671089 >> 24, n // 25)
        for v, want in ((0, 0), (12, 0), (24, 0), (25, 1), (49, 1), (1_632_012, 65280)):
            self.assertEqual(self.ref.div25_exact(v), want)

    def test_ratio_bounds_random_windows_and_rounding(self):
        rng = np.random.default_rng(205)
        windows = rng.integers(0, 256, (20000, 25), dtype=np.int64)
        s1 = windows.sum(axis=1)
        vs = 25 * (windows * windows).sum(axis=1) - s1*s1
        # 10,143,900 is attained by 12 zeros and 13 255s.
        vs = np.concatenate(([0, 1, 10_143_900], vs))
        for eps in EPSILONS:
            expected = np.array([(4096*int(v)+(int(v)+625*eps)//2)//(int(v)+625*eps)
                                 for v in vs], dtype=np.int64)
            np.testing.assert_array_equal(self.ref.ratio_q12(vs, eps), expected)
            self.assertLessEqual(int(expected.max()), 4092)
        self.assertEqual(self.ref.ratio_q12(10_143_900, 16), 4092)
        # V=7567*epsilon gives exact unrounded Q12 ratio 3783.5.
        # Neighbours catch > instead of >= at the rounding boundary.
        for eps in EPSILONS:
            self.assertEqual(self.ref.ratio_q12(7567*eps-1, eps), 3783)
            self.assertEqual(self.ref.ratio_q12(7567*eps, eps), 3784)
            self.assertEqual(self.ref.ratio_q12(7567*eps+1, eps), 3784)
        self.assertEqual(self.ref.ratio_q12(40000, 64), 2048)

    def test_signed_ties_unsigned_gain_and_clamp(self):
        raw = np.array([[100, 100, 100, 0, 255]], dtype=np.uint8)
        base = np.array([[25472, 25728, 25471, 256, 65024]], dtype=np.int64)
        # +/-0.5 Q8 rounds away from zero before final half-up pixel rounding.
        np.testing.assert_array_equal(self.ref.enhance_fixed(raw, base, 0, 1),
                                      [[100, 100, 100, 1, 254]])
        np.testing.assert_array_equal(self.ref.enhance_fixed(raw, base, 0, 512),
                                      [[101, 100, 101, 0, 255]])
        np.testing.assert_array_equal(self.ref.enhance_fixed(raw, base, 16, 512),
                                      [[100, 101, 99, 1, 254]])
        # Output and gain ties: B=100+128/256, residual=-128; E8=-1 for G=1.
        self.assertEqual(int(self.ref.enhance_fixed(raw[:, :1], base[:, 1:2], 0, 1)[0, 0]), 100)
        # Limit L=16: a difference of 100 adds at most 32 at G=512.
        np.testing.assert_array_equal(self.ref.enhance_fixed(np.array([[200, 0]], np.uint8),
                                      np.array([[25600, 25600]], np.int64), 0, 512), [[132, 68]])

    def test_all_constants_eps_modes_and_parameter_extrema(self):
        for level, eps, mode, threshold, gain in itertools.product(
                range(256), EPSILONS, MODES, (0, 16), (0, 512)):
            if mode == "DENOISE":
                gain = 256
            image = np.full((16, 16), level, dtype=np.uint8)
            for fn in (self.ref.filter_fixed, self.ref.filter_float):
                result = fn(image, eps, threshold, gain, mode)
                self.assertTrue(np.all(result == level), (level, eps, mode, threshold, gain))

    def test_inclusive_configuration_guards(self):
        image = np.zeros((16, 16), dtype=np.uint8)
        for fn in (self.ref.filter_fixed, self.ref.filter_float):
            for eps, threshold, gain, mode, limit in (
                    (0, 0, 0, "RAW", 16), (63, 0, 0, "RAW", 16),
                    (64, -1, 0, "RAW", 16), (64, 17, 0, "RAW", 16),
                    (64, 0, -1, "RAW", 16), (64, 0, 513, "RAW", 16),
                    (64, 0, 1.5, "RAW", 16), (64, 0, True, "RAW", 16),
                    (64, 0, 0, "raw", 16), (64, 0, 0, "DENOISE", 16),
                    (64, 0, 0, "RAW", 15)):
                with self.assertRaises((TypeError, ValueError)):
                    fn(image, eps, threshold, gain, mode, limit)
            for bad in (image.astype(float), image.astype(np.int64), image[None],
                        image[:15], np.zeros((481, 16), np.uint8), np.zeros((16, 641), np.uint8), [[0]*16]*16):
                with self.assertRaises((TypeError, ValueError)):
                    fn(bad, 64, 0, 256, "RAW")
        for bad in (-1, 1_632_013, 1.0, True, np.array([1.0]), np.array([2**64-1], np.uint64)):
            with self.assertRaises((TypeError, ValueError)):
                self.ref.div25_exact(bad)
        for bad in (-1, 10_143_901, 1.5, True):
            with self.assertRaises((TypeError, ValueError)):
                self.ref.ratio_q12(bad, 64)
        for raw, base in ((np.array([0], np.uint8), np.array([0], np.int64)),
                          (image, np.zeros((16, 17), np.int64)),
                          (image, image.astype(float)),
                          (image, np.full((16, 16), -1, np.int64)),
                          (image, np.full((16, 16), 65281, np.int64))):
            with self.assertRaises((TypeError, ValueError)):
                self.ref.enhance_fixed(raw, base, 0, 256)

    def test_patterns_frame_wrap_and_block_edges(self):
        for f in (0, 255, 256, 2**32 - 1, 2**32, 2**32 + 1):
            p = self.ref.pattern(640, 480, f)
            self.assertEqual(p.shape, (480, 640))
            self.assertEqual(p.dtype, np.uint8)
            for y, x in ((0, 0), (479, 639), (15, 16)):
                self.assertEqual(int(p[y, x]), (x+y+f) % 256)
        checker = self.ref.pattern(640, 480, 0, 1)
        self.assertEqual([int(checker[0, x]) for x in (0, 15, 16, 31, 32)], [32,32,224,224,32])
        self.assertEqual(int(checker[16, 16]), 32)
        step = self.ref.pattern(17, 19, 0, 2)
        self.assertTrue(np.all(step[:, :9] == 32))
        self.assertTrue(np.all(step[:, 9:] == 224))
        self.assertTrue(np.all(self.ref.pattern(16, 16, 123, 3) == 128))
        for args in ((15, 16, 0, 0), (641, 16, 0, 0), (16, 481, 0, 0),
                     (16, 16, -1, 0), (16, 16, 1.5, 0), (16, 16, 0, 4)):
            with self.assertRaises((TypeError, ValueError)):
                self.ref.pattern(*args)

    def test_intermediate_ledger_extrema_and_exact_coefficient_center(self):
        for image in (np.zeros((16, 16), np.uint8), np.full((16, 16), 255, np.uint8),
                      ((np.indices((16,16)).sum(axis=0) % 2)*255).astype(np.uint8)):
            for eps in EPSILONS:
                layers = self.ref.fixed_layers(image, eps)
                np.testing.assert_array_equal(layers["raw"], image[4:-4, 4:-4])
                for name, maximum in (("s1",6375), ("s2",1625625), ("variance_numerator",10143900),
                                      ("denominator",10783900), ("a_q12",4092), ("mean_q8",65280),
                                      ("b_q8",65280), ("sum_a",102300), ("sum_b",1632000),
                                      ("abar_q12",4092), ("bbar_q8",65280), ("base_q8",65280)):
                    values = layers[name]
                    self.assertEqual(values.dtype, np.int64, name)
                    self.assertGreaterEqual(int(values.min()), 0, name)
                    self.assertLessEqual(int(values.max()), maximum, name)
                np.testing.assert_array_equal(layers["center"], image[2:-2,2:-2])
                self.assertEqual(layers["a_q12"].shape, (12,12))
                self.assertEqual(layers["base_q8"].shape, (8,8))
        self.assertEqual(int(layers["variance_numerator"].max()),10143900)

    def test_vga_structured_random_final_error_one_lsb(self):
        rng = np.random.default_rng(700)
        yy, xx = np.indices((480,640))
        images = [self.ref.pattern(640,480,255,p) for p in range(4)]
        images += [rng.integers(0,256,(480,640),dtype=np.uint8),
                   ((xx+yy >= 500)*192+32).astype(np.uint8),
                   ((xx%4 < 2)*128+64).astype(np.uint8),
                   np.clip(128+rng.normal(0,8,(480,640)),0,255).round().astype(np.uint8)]
        impulse = np.zeros((480,640),np.uint8)
        impulse[240,320] = 255
        images.append(impulse)
        configs = (("RAW",0,0), ("BASE",16,512), ("DENOISE",0,256),
                   ("DENOISE",16,256), ("ENHANCE",0,0), ("ENHANCE",16,0),
                   ("ENHANCE",0,512), ("ENHANCE",16,512))
        hist = np.zeros(2, dtype=np.int64)
        for k, image in enumerate(images):
            for eps in EPSILONS:
                for mode, threshold, gain in configs:
                    fixed = self.ref.filter_fixed(image,eps,threshold,gain,mode)
                    floating = self.ref.filter_float(image,eps,threshold,gain,mode)
                    self.assertEqual(fixed.shape,(472,632))
                    error = np.abs(fixed.astype(np.int16)-floating.astype(np.int16))
                    self.assertLessEqual(int(error.max()),1,(k,eps,mode,threshold,gain))
                    hist += np.bincount(error.ravel(),minlength=2)
        print(f"VGA numerical gate: {len(images)*len(EPSILONS)*len(configs)} cases; "
              f"error histogram 0/1 LSB={hist.tolist()}; "
              f"MAE={hist[1]/hist.sum():.9f}; RMSE={np.sqrt(hist[1]/hist.sum()):.9f}", flush=True)

    def test_local_raw_96_produces_same_central_88(self):
        image = np.random.default_rng(300).integers(0,256,(480,640),dtype=np.uint8)
        for y,x in ((4,4),(192,272),(380,540)):
            raw_roi = image[y:y+96,x:x+96]
            for eps in EPSILONS:
                for mode in MODES:
                    g = 256 if mode == "DENOISE" else 448
                    for fn in (self.ref.filter_fixed,self.ref.filter_float):
                        full = fn(image,eps,4,g,mode)
                        local = fn(raw_roi,eps,4,g,mode)
                        np.testing.assert_array_equal(local, full[y:y+88,x:x+88])


if __name__ == "__main__":
    unittest.main()
