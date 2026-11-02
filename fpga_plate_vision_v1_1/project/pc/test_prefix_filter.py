import unittest
import numpy as np
from segment_ref import segment_frame,filter_prefix_candidates

class PrefixTests(unittest.TestCase):
    def test_center_boundary_and_order(self):
        boxes=[(2,10,12,20),(8,11,4,19),(16,10,5,20),(60,10,15,20)]
        self.assertEqual(filter_prefix_candidates(boxes,80),boxes[1:])
    def test_translated_roi_does_not_delete_first_letter(self):
        for left in [0,30,70]:
            a=np.full((120,160),230,np.uint8)
            a[30:50,left+2:left+5]=0
            a[30:50,left+16:left+21]=0
            a[30:50,left+35:left+40]=0
            roi=(left,20,left+80,70)
            original=segment_frame(a,roi)
            cleaned=segment_frame(a,roi,skip_prefix=True)
            self.assertEqual(len(original['boxes']),3)
            self.assertEqual(cleaned['boxes'],original['boxes'][1:])
    def test_default_and_empty(self):
        a=np.full((120,160),100,np.uint8)
        self.assertEqual(segment_frame(a,(0,0,160,120),skip_prefix=True)['boxes'],[])
        self.assertEqual(filter_prefix_candidates([(1,1,2,5)],7),[(1,1,2,5)])

if __name__=='__main__':unittest.main()
