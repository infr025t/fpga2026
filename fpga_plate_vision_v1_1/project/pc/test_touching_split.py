import unittest
import numpy as np
from segment_ref import segment_mask, segment_frame


class TouchingTests(unittest.TestCase):
    def test_thin_bridge_and_translation(self):
        for x, y in [(3, 4), (35, 20), (110, 60)]:
            m = np.zeros((100, 160), bool)
            m[y:y+24, x:x+10] = True
            m[y:y+24, x+16:x+26] = True
            m[y+23, x:x+26] = True
            self.assertEqual(segment_mask(m)['boxes'], [(x, y, 26, 24)])
            self.assertEqual(segment_mask(m, split_touching=True)['boxes'],
                             [(x, y, 11, 24), (x+11, y, 15, 24)])

    def test_wide_solid_and_m_w_not_split(self):
        for kind in ['solid', 'M', 'W']:
            m = np.zeros((70, 80), bool)
            if kind == 'solid':
                m[20:44, 20:47] = True
            else:
                m[20:44, 20:23] = True
                m[20:44, 44:47] = True
                for dx in range(27):
                    yy = int(round(min(dx, 26-dx)*20/13))
                    yy = yy if kind == 'M' else 20-yy
                    m[20+yy:23+yy, 20+dx] = True
            old = segment_mask(m)
            self.assertEqual(segment_mask(m, split_touching=True), old)

    def test_blank_and_narrow(self):
        m = np.zeros((40, 60), bool)
        self.assertEqual(segment_mask(m, split_touching=True)['boxes'], [])
        m[8:30, 20:30] = True
        self.assertEqual(segment_mask(m, split_touching=True), segment_mask(m))

    def test_current_frame_separates_geometry_only(self):
        from pathlib import Path
        import json
        root = Path(__file__).resolve().parents[1]
        p = sorted((root.parent/'evidence/baseline/reports/prefix_board_20/frames').glob('*/result.json'))[0]
        r = json.loads(p.read_text()); raw = np.load(p.parent/'raw.npy')
        old = segment_frame(raw, r['roi'], skip_prefix=True)
        new = segment_frame(raw, r['roi'], skip_prefix=True, split_touching=True)
        self.assertEqual(len(old['boxes']), 6)
        self.assertEqual(len(new['boxes']), 7)
        self.assertEqual(new['boxes'][:5], old['boxes'][:5])
        self.assertLessEqual(new['boxes'][-2][0]+new['boxes'][-2][2], new['boxes'][-1][0])


if __name__ == '__main__':
    unittest.main()
