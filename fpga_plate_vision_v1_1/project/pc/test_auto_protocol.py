import struct
import unittest
import zlib
from auto_protocol import StreamParser,decode_packet

def packet(magic, body):
    data = magic + body
    return data + struct.pack('<I', zlib.crc32(data))

class ProtocolTests(unittest.TestCase):
    def test_dynamic_roi_packet(self):
        roi=bytes((13,54,148,90));box=bytes((29,64,14,26))
        data=packet(b'ASG2',struct.pack('<4I',9,0,115441,1)+roi+box+bytes(252))
        p=decode_packet(data)
        self.assertEqual(p['roi'],tuple(roi));self.assertEqual(p['boxes'],[tuple(box)])
        self.assertEqual(p['magic'],'ASG2')
        empty=packet(b'ASG2',struct.pack('<4I',10,0,57601,0)+bytes(260))
        self.assertEqual(decode_packet(empty)['roi'],(0,0,0,0))
        invalid=packet(b'ASG2',struct.pack('<4I',9,0,115441,1)+bytes(4)+box+bytes(252))
        with self.assertRaises(ValueError):decode_packet(invalid)
        prefixed=packet(b'ASG3',struct.pack('<4I',9,0,115441,1)+roi+box+bytes(252))
        self.assertEqual(decode_packet(prefixed)['magic'],'ASG3')
        for magic in [b'ASG4',b'ASG5']:
            split=packet(magic,struct.pack('<4I',9,0,115441,1)+roi+box+bytes(252))
            self.assertEqual(decode_packet(split)['magic'],magic.decode())
    def test_resync_and_fragmentation(self):
        good = packet(b'AER1', struct.pack('<7I', 7, 0, 2, 123, 4, 5, 6) + b'AB' + bytes(62))
        parser = StreamParser()
        result = []
        stream = b'AIF1' + bytes(98) + good[:-1] + bytes([good[-1]^1]) + good
        for byte in stream:
            result += parser.feed(bytes([byte]))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['text'], b'AB')
        self.assertEqual(result[0]['frame_id'], 7)

    def test_strict_fields(self):
        bad = packet(b'AER1', struct.pack('<7I', 7, 0, 65, 123, 4, 5, 6) + bytes(64))
        self.assertEqual(StreamParser().feed(bad), [])

if __name__ == '__main__':
    unittest.main()
