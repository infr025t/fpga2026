import unittest,importlib.util
import numpy as np

class ReferenceContract(unittest.TestCase):
 def test_reference_and_literal_windows(self):
  spec=importlib.util.find_spec('model.reference')
  self.assertIsNotNone(spec,'new two-filter Sobel reference is missing')
  from model import reference as r
  a=np.full((19,23),128,np.uint8)
  self.assertTrue(np.all(r.gaussian3(a)==128))
  self.assertTrue(np.all(r.guided_base(a,64)==128))
  impulse=np.zeros((7,7),np.uint8);impulse[3,3]=128
  np.testing.assert_array_equal(r.gaussian3(impulse)[1:4,1:4],[[8,16,8],[16,32,16],[8,16,8]])
  step=np.array([[0,0,20]]*3,np.uint8)
  self.assertEqual(int(r.sobel(step,80)[0,0]),255)
  self.assertEqual(int(r.sobel(step,81)[0,0]),0)
  for f in [0,1]:
   raw,edge=r.process(a,f,64,160)
   self.assertEqual(raw.shape,(9,13));np.testing.assert_array_equal(raw,a[5:-5,5:-5])
   self.assertTrue(np.all(edge==0))

if __name__=='__main__':unittest.main()
