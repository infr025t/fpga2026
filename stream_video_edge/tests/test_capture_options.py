import sys,unittest,contextlib,io
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'pc'))
from receive import parse_args

class CaptureOptionsTests(unittest.TestCase):
 def test_exact_fifty_and_legacy_rounds(self):
  a=parse_args(['--auto','--frames','50']);self.assertEqual(a.frames,50)
  self.assertEqual(parse_args(['--auto','--rounds','3']).frames,12)
  self.assertEqual(parse_args(['--auto']).frames,4)
  self.assertEqual(parse_args([]).frames,1)
 def test_invalid_or_ambiguous_count(self):
  for args in (['--frames','50'],['--rounds','2'],['--auto','--frames','0'],['--auto','--frames','101'],['--auto','--frames','50','--rounds','2']):
   with self.subTest(args=args),contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):parse_args(args)

if __name__=='__main__':unittest.main()
