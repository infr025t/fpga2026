import unittest
from pathlib import Path
import numpy as np
from model import reference as r
ROOT=Path(__file__).resolve().parents[1]
class GaussianChoice(unittest.TestCase):
 def test_guided_branch_removed(self):
  names={p.name for p in (ROOT/'rtl/core').glob('*.sv')}
  self.assertEqual(names,{'edge_core.sv','gaussian3.sv','sobel3.sv','row_window3.sv'})
  self.assertFalse(hasattr(r,'guided_base'))
 def test_default_matches_previous_gaussian_result(self):
  a=r.pattern(640,480,7)
  raw,edge=r.process(a,threshold=128)
  import zlib
  self.assertEqual(raw.shape,(470,630))
  self.assertEqual(zlib.crc32(edge.tobytes()),207516)
 def test_no_filter_selector_on_lcd_adapter(self):
  self.assertNotIn('filter_id',(ROOT/'rtl/runtime/video_core_adapter.sv').read_text())
if __name__=='__main__':unittest.main()
