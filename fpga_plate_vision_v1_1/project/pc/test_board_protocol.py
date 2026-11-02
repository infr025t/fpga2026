import unittest,struct,zlib,tempfile,subprocess,sys,json
from pathlib import Path
import numpy as np
try:
    from board_protocol import pack_request,unpack_response
except ImportError:
    pack_request=unpack_response=None

class ProtocolTests(unittest.TestCase):
    def test_request_layout_and_crc(self):
        self.assertIsNotNone(pack_request,'board protocol not implemented')
        x=np.arange(768,dtype=np.uint16).astype(np.uint8).reshape(32,24)
        p=pack_request(0x12345678,x)
        self.assertEqual(len(p),780)
        self.assertEqual(p[:8],b'CNN1\x78\x56\x34\x12')
        self.assertEqual(p[8:776],x.tobytes())
        self.assertEqual(struct.unpack('<I',p[-4:])[0],zlib.crc32(p[:-4]))
    def test_signed_scores_and_reject_corruption(self):
        self.assertIsNotNone(unpack_response,'board protocol not implemented')
        values=np.arange(-18,18,dtype='<i4')*1001
        body=b'CNR1'+struct.pack('<II',71,942444)+values.tobytes()
        packet=body+struct.pack('<I',zlib.crc32(body))
        cycles,scores=unpack_response(packet,71)
        self.assertEqual(cycles,942444);np.testing.assert_array_equal(values,scores)
        with self.assertRaises(ValueError):unpack_response(packet,72)
        with self.assertRaises(ValueError):unpack_response(packet[:30]+bytes([packet[30]^1])+packet[31:],71)
        with self.assertRaises(ValueError):unpack_response(packet[:-1],71)
    def test_empty_scene_is_failure_before_opening_port(self):
        import cv2
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);frames=root/'frames';frames.mkdir()
            cv2.imwrite(str(frames/'empty_selected.png'),np.full((120,160),255,np.uint8))
            result=subprocess.run([sys.executable,str(Path(__file__).with_name('verify_board.py')),
                                   '--frames',str(frames),'--out',str(root/'out'),'--port','COM_DO_NOT_OPEN'],
                                  capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            summary=json.loads((root/'out/summary.json').read_text())
            self.assertEqual(summary['status'],'FAIL')
            self.assertIn('No characters',summary['error'])

if __name__=='__main__':unittest.main()
