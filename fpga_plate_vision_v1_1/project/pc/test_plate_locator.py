import unittest
import numpy as np
from plate_locator import locate_plate

class LocatorTests(unittest.TestCase):
    def test_blank_and_low_contrast(self):
        for value in [0,90,255]:
            self.assertIsNone(locate_plate(np.full((120,160),value,np.uint8)))
        a=np.full((120,160),80,np.uint8);a[30:65,10:150]=95
        self.assertIsNone(locate_plate(a))
    def test_translation(self):
        # 白底区域边界来自像素，而不是预存位置或识别答案。
        for dx in [-8,0,6]:
            for dy in [-24,0,28]:
                a=np.full((120,160),40,np.uint8)
                x,y=12+dx,35+dy;a[y:y+36,x:x+140]=230
                for cx in range(x+10,x+125,18):a[y+8:y+30,cx:cx+6]=20
                self.assertEqual(locate_plate(a),(x,y-3,x+139,y+35))
    def test_reject_truncated_and_oversized(self):
        for y,h in [(0,36),(90,30),(10,80)]:
            a=np.full((120,160),40,np.uint8);a[y:y+h,10:150]=230
            self.assertIsNone(locate_plate(a))
    def test_largest_bright_band_not_first(self):
        a=np.full((120,160),20,np.uint8);a[5:20,20:90]=240;a[60:96,10:150]=240
        self.assertEqual(locate_plate(a),(10,57,149,95))
    def test_two_pixel_hole_in_header(self):
        a=np.full((120,160),20,np.uint8);a[30:66,10:150]=240;a[30:66,60:62]=0
        self.assertEqual(locate_plate(a),(10,27,149,65))

if __name__=='__main__':unittest.main()
