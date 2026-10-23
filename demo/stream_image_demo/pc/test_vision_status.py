import binascii
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

import vision_status


def packet(base=100, flags=9, version=1, length=58):
    header = b'VST1' + struct.pack('<BBH', version, flags, length)
    header += b''.join(struct.pack('<I', (base + 17 * i) & 0xffffffff) for i in range(12))
    return header + struct.pack('<H', binascii.crc_hqx(header[4:], 0xffff))


class VisionStatusTests(unittest.TestCase):
    def test_fragmented_status_snapshots_keep_all_counters_and_flags(self):
        decoder = vision_status.StatusParser()
        statuses = []
        for value in packet(100, 9) + packet(200, 2):
            statuses.extend(decoder.feed(bytes([value])))
        self.assertEqual(len(statuses), 2)
        self.assertEqual([status['frame_id'] for status in statuses], [100, 200])
        for index, status in enumerate(statuses):
            self.assertEqual([status[key] for key in vision_status.FIELDS],
                             [(index + 1) * 100 + i * 17 for i in range(12)])
        self.assertTrue(statuses[0]['configured'] and statuses[0]['pattern'])
        self.assertTrue(statuses[1]['camera_fault'])
        self.assertFalse(statuses[1]['configured'] or statuses[1]['pattern'])
        self.assertEqual(decoder.rejected, 0)
        self.assertFalse(decoder.finish())

    def test_bad_crc_version_flags_and_size_resynchronize(self):
        damaged = bytearray(packet())
        damaged[30] ^= 1
        bad = [damaged, packet(version=2), packet(flags=16), packet(length=57)]
        for candidate in bad:
            with self.subTest(header=candidate[:8]):
                decoder = vision_status.StatusParser()
                statuses = decoder.feed(candidate + packet(300))
                self.assertEqual([s['frame_id'] for s in statuses], [300])
                self.assertGreater(decoder.rejected, 0)

    def test_noise_is_bounded_and_truncated_connection_is_discarded(self):
        decoder = vision_status.StatusParser()
        self.assertEqual(decoder.feed(b'x' * 100000), [])
        self.assertLessEqual(len(decoder.buffer), 3)
        self.assertEqual(decoder.feed(packet()[:20]), [])
        self.assertTrue(decoder.finish())
        self.assertEqual(decoder.feed(packet(400))[0]['frame_id'], 400)
        self.assertFalse(decoder.finish())

    def test_unsigned_counter_wrap_values_are_preserved(self):
        status = vision_status.StatusParser().feed(packet(0xffffffff, flags=15))[0]
        self.assertEqual(status['frame_id'], 0xffffffff)
        self.assertEqual(status['processed_frames'], 16)
        self.assertTrue(status['paused'])

    def test_cli_preserves_old_logs_and_counts_complete_status_packets(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            path = root / 'wire.bin';path.write_bytes(packet(100) + packet(200) + packet(300)[:20])
            out = root / 'logs';out.mkdir()
            (out / 'status_0000000001.json').write_text('historical status')
            command = [sys.executable, str(Path(vision_status.__file__)), '--input', str(path),
                       '--out', str(out), '--count', '2']
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Received 2 valid status packets', result.stdout)
            self.assertEqual((out / 'status_0000000001.json').read_text(), 'historical status')
            self.assertEqual(json.loads((out / 'status_0000000002.json').read_text())['frame_id'], 100)
            self.assertEqual(json.loads((out / 'status_0000000003.json').read_text())['frame_id'], 200)
            self.assertEqual(len(list(out.glob('*.json'))), 3)

    def test_cli_reports_incomplete_eof_and_missing_requested_packets(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d);path = root / 'wire.bin';path.write_bytes(packet() + packet(200)[:20])
            script = str(Path(vision_status.__file__))
            result = subprocess.run([sys.executable, script, '--input', str(path), '--out', str(root / 'a')],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertIn('incomplete status packet', result.stderr)
            path.write_bytes(packet())
            result = subprocess.run([sys.executable, script, '--input', str(path),
                                     '--out', str(root / 'b'), '--count', '2'],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertIn('requested status count', result.stderr)


if __name__ == '__main__':
    unittest.main()
