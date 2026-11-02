"""分割合同边界测试；预期不依赖待测分割器。"""
import importlib.util
import unittest
import tempfile
from pathlib import Path
import cv2
import numpy as np

spec=importlib.util.find_spec('segment_ref')
s=__import__('segment_ref') if spec else None


class SegmentTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(s,'segment_ref implementation is required')

    def test_boxmean_replicates_tiny_roi_and_rounds(self):
        a=np.array([[0,255]],np.uint8)
        np.testing.assert_array_equal(s.mean15(a),[[119,136]])
        rng=np.random.default_rng(128)
        for h,w in [(1,1),(2,7),(9,3),(17,19)]:
            a=rng.integers(0,256,(h,w),dtype=np.uint8)
            want=np.zeros((h,w),np.int32)
            for y in range(h):
                for x in range(w):
                    total=sum(int(a[min(h-1,max(0,y+dy)),min(w-1,max(0,x+dx))]) for dy in range(-7,8) for dx in range(-7,8))
                    want[y,x]=(total+112)//225
            np.testing.assert_array_equal(s.mean15(a),want)

    def test_threshold_inclusive_minus12_and_unsigned_underflow(self):
        a=np.full((21,21),100,np.uint8);a[10,10]=88
        self.assertTrue(s.threshold(a)[10,10])
        a[10,10]=89;self.assertFalse(s.threshold(a)[10,10])
        self.assertFalse(s.threshold(np.zeros((5,5),np.uint8)).any())
        rng=np.random.default_rng(44)
        for h,w in [(1,1),(3,7),(24,31)]:
            a=rng.integers(0,256,(h,w),dtype=np.uint8)
            np.testing.assert_array_equal(s.threshold(a),cv2.adaptiveThreshold(a,255,cv2.ADAPTIVE_THRESH_MEAN_C,cv2.THRESH_BINARY_INV,15,12)>0)

    def test_eight_connected_diagonal_rowmajor_and_full_queue(self):
        a=np.array([[1,0,0,1],[0,1,0,0],[0,0,1,0]],bool)
        self.assertEqual(s.components(a),[(0,0,3,3,3),(3,0,1,1,1)])
        self.assertEqual(s.components(np.ones((120,160),bool)),[(0,0,160,120,19200)])
        self.assertEqual(s.components(np.zeros((2,3),bool)),[])

    def test_height_round_even_and_filter_boundaries(self):
        self.assertEqual(s.height_limits(65),(6,55))
        self.assertEqual(s.height_limits(70),(7,60))
        self.assertEqual(s.height_limits(50),(5,42))
        boxes=[(0,0,7,5,5),(10,0,8,5,40),(20,0,2,5,4),(30,0,1,5,5),(40,0,2,4,8)]
        self.assertEqual(s.candidates(boxes,50),[(0,0,7,5)])

    def test_group_strict_center_boundary_and_stable_tie(self):
        boxes=[(50,0,2,10),(0,9,2,10),(20,30,2,10)]
        self.assertEqual(s.select_group(boxes),[(50,0,2,10)])
        self.assertEqual(s.select_group([(10,0,2,10),(10,1,2,10),(0,2,2,10)]),[(0,2,2,10),(10,0,2,10),(10,1,2,10)])

    def test_group_height_ratio_and_fractional_median(self):
        # 中位数10.5，6不能通过，7可通过；每个成员都满足与10高基线的条件。
        boxes=[(0,8,2,6),(10,7,2,7),(20,5,2,10),(30,5,2,11),(40,4,2,12),(50,4,2,12)]
        self.assertEqual(s.select_group(boxes),boxes[1:])
        self.assertEqual(s.select_group([(0,0,2,10),(5,0,2,20)]),[(5,0,2,20)])

    def test_candidate_overflow_has_no_partial_boxes(self):
        a=np.zeros((120,160),bool)
        for y in range(0,98,14):
            for x in range(0,150,10):a[y:y+12,x:x+2]=1
        result=s.segment_mask(a)
        self.assertEqual(result['status'],3)
        self.assertEqual(result['boxes'],[])
        self.assertEqual(result['candidate_count'],65)

    def test_roi_local_edges_absolute_boxes_flags_and_invalid(self):
        raw=np.full((120,160),230,np.uint8);raw[23:33,31:34]=0
        roi=(30,20,50,40)
        want=[(31,23,3,10)]
        self.assertEqual(s.segment_frame(raw,roi)['boxes'],want)
        outside=raw.copy();outside[:20]=0;outside[40:]=0;outside[:,:30]=0;outside[:,50:]=0
        self.assertEqual(s.segment_frame(outside,roi)['boxes'],want)
        for flags in range(4):
            source=raw[::-1,::-1] if flags&1 else raw.copy()
            if flags&2:source=255-source
            self.assertEqual(s.segment_frame(source,roi,flags)['boxes'],want)
        for invalid in [(0,0,161,120),(5,5,5,6),(0,0,4,121)]:
            self.assertEqual(s.segment_frame(raw,invalid)['status'],1)
        self.assertEqual(s.segment_frame(raw,roi,4)['status'],1)

    def test_vector_export_preserves_full_raw_and_overflow_evidence(self):
        self.assertTrue(hasattr(s,'export_frame_vectors'),'frame vector exporter required')
        with tempfile.TemporaryDirectory() as temp:
            entries=s.export_frame_vectors(temp)
            self.assertGreaterEqual(len(entries),15);self.assertLessEqual(len(entries),25)
            for entry in entries:
                values=(Path(temp)/(entry['name']+'.frame.mem')).read_text().split()
                self.assertEqual(len(values),19200)
            named={e['name']:e for e in entries}
            self.assertEqual(named['candidates64']['candidate_count'],64)
            self.assertEqual(named['candidates64']['status'],0)
            self.assertEqual(named['overflow65']['candidate_count'],65)
            self.assertEqual(named['overflow65']['status'],3)
            self.assertEqual(named['corner_origin']['boxes'],[(0,0,3,15)])
            self.assertIn('invalid_far_roi',named)
            self.assertEqual(named['invalid_far_roi']['status'],1)


if __name__=='__main__':unittest.main()
