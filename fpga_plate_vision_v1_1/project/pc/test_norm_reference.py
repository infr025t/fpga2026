"""整数归一化：独立有理数 oracle 与边界回归。"""
import unittest
from fractions import Fraction
import numpy as np
import norm_ref as n


def area_oracle(a, width, height):
    sh, sw = a.shape
    out = np.zeros((height, width), np.uint8)
    for y in range(height):
        ya, yb = Fraction(y*sh, height), Fraction((y+1)*sh, height)
        for x in range(width):
            xa, xb = Fraction(x*sw, width), Fraction((x+1)*sw, width)
            total = Fraction(0)
            for j in range(sh):
                wy = max(Fraction(0), min(yb,j+1)-max(ya,j))
                for i in range(sw):
                    wx = max(Fraction(0), min(xb,i+1)-max(xa,i))
                    total += int(a[j,i])*wx*wy
            value = total/((xb-xa)*(yb-ya))
            out[y,x] = (2*value.numerator+value.denominator)//(2*value.denominator)
    return out


class NormTests(unittest.TestCase):
    def test_percentile_exact_rank(self):
        a = np.array([0,10,20,30],np.uint8)
        self.assertEqual(n.percentile100(a,3),90)
        self.assertEqual(n.percentile100(a,85),2550)
        self.assertEqual(n.percentile100(np.array([73],np.uint8),85),7300)

    def test_percentile_independent_sorted_oracle(self):
        rng=np.random.default_rng(893)
        for count in [1,2,3,7,99,100,101,253]:
            a=rng.integers(0,256,count,dtype=np.uint8)
            ordered=sorted(map(int,a))
            for p in [0,3,85,100]:
                rank=Fraction((count-1)*p,100);lo=rank.numerator//rank.denominator
                expected=ordered[lo]+(ordered[min(lo+1,count-1)]-ordered[lo])*(rank-lo)
                self.assertEqual(n.percentile100(a,p),expected*100)

    def test_contrast_known_floor_difference_and_clip(self):
        a=np.array([[0,10,20,30]],np.uint8)
        c,m=n.contrast(a)
        self.assertEqual(m['high'],25)
        self.assertEqual(m['den'],24)
        np.testing.assert_array_equal(c,[[255,159,53,0]])

    def test_area_matches_fraction_oracle(self):
        rng=np.random.default_rng(619)
        for sh,sw,dw,dh in [(1,1,7,9),(1,3,7,1),(3,1,1,7),(3,5,2,2),(3,2,5,7),(5,7,4,9)]:
            a=rng.integers(0,256,(sh,sw),dtype=np.uint8)
            np.testing.assert_array_equal(n.area_resize(a,dw,dh),area_oracle(a,dw,dh))

    def test_area_half_up_and_identity(self):
        a=np.array([[0,1],[0,1]],np.uint8)
        np.testing.assert_array_equal(n.area_resize(a,1,1),[[1]])
        np.testing.assert_array_equal(n.area_resize(a,2,2),a)

    def test_ties_even_geometry(self):
        self.assertEqual(n.round_even(5,2),2)
        self.assertEqual(n.round_even(7,2),4)
        self.assertEqual(n.fit_dimensions(44,9),(22,4))
        self.assertEqual(n.fit_dimensions(44,7),(22,4))
        self.assertEqual(n.fit_dimensions(1,100),(1,30))
        self.assertEqual(n.fit_dimensions(100,1),(22,1))

    def test_flat_tiny_center_and_border(self):
        for shape in [(1,1),(2,1),(1,2),(60,110)]:
            patch,meta=n.normalize_crop(np.full(shape,173,np.uint8))
            self.assertEqual(patch.shape,(32,24))
            self.assertEqual(patch.dtype,np.uint8)
            self.assertFalse(patch.any())
            self.assertEqual(meta['den'],16)
        a=np.array([[0,255]],np.uint8)
        patch,meta=n.normalize_crop(a)
        self.assertEqual((meta['nw'],meta['nh']),(22,11))
        self.assertEqual((meta['dst_x'],meta['dst_y']),(1,10))
        self.assertFalse(patch[[0,-1]].any())
        self.assertFalse(patch[:,[0,-1]].any())

    def test_roi_clipping_excludes_outside_values(self):
        a=np.full((20,20),255,np.uint8);a[5:12,6:14]=0
        patch,m=n.feature_patch_int(a,(6,5,8,7),roi=(6,5,14,12))
        self.assertEqual(m['crop_xyxy'],[6,5,14,12])
        self.assertFalse(patch.any())
        patch,m=n.feature_patch_int(a,(0,0,1,1))
        self.assertEqual(m['crop_xyxy'],[0,0,3,3])

    def test_reject_invalid_inputs(self):
        for a in [np.zeros((0,2),np.uint8),np.zeros((2,2),np.float32),np.zeros((2,2,3),np.uint8)]:
            with self.assertRaises(ValueError):n.normalize_crop(a)
        with self.assertRaises(ValueError):n.feature_patch_int(np.zeros((4,4),np.uint8),(8,8,1,1))
        with self.assertRaises(ValueError):n.feature_patch_int(np.zeros((4,4),np.uint8),(0,0,0,1))
        with self.assertRaises(ValueError):n.feature_patch_int(np.zeros((4,4),np.uint8),(0,0,2,2),roi=(1,1,4,4))
        with self.assertRaises(ValueError):n.feature_patch_int(np.zeros((4,4),np.uint8),(2,2,3,1))

    def test_frame_flags_use_logical_coordinates(self):
        a=np.arange(120*160,dtype=np.uint8).reshape(120,160)
        box=(7,9,12,27);roi=(5,8,27,41)
        for flags in range(4):
            logical=a[::-1,::-1] if flags&1 else a
            if flags&2:logical=255-logical
            expected,_=n.feature_patch_int(logical,box,roi)
            actual,_=n.normalize_frame(a,box,roi,flags)
            np.testing.assert_array_equal(actual,expected)
        with self.assertRaises(ValueError):n.normalize_frame(a,box,roi,4)
        with self.assertRaises(ValueError):n.normalize_frame(a[:10],box,roi,0)


if __name__=='__main__':unittest.main()
