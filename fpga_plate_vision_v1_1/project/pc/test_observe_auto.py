"""只读观察器端到端回放：覆盖真参考、丢包、篡改及分组边界。"""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

import numpy as np
import integer_cnn
from norm_ref import normalize_frame
from segment_ref import segment_frame

ROOT = Path(__file__).resolve().parents[1]


def packet(magic, body):
    data = magic + body
    return data + struct.pack('<I', zlib.crc32(data))


def fixture(frame_id=1, character=False, change=None):
    raw = np.full((120, 160), 230, np.uint8)
    if character:
        raw[45:67, 50:54] = 0
    roi = (26, 35, 158, 87)
    boxes = segment_frame(raw, roi)['boxes']
    assert len(boxes) == int(character)
    raw_crc = zlib.crc32(raw.tobytes()) ^ (1 if change == 'raw_crc' else 0)
    aif = packet(b'AIF1', struct.pack('<II4BB3x', frame_id, 100, *roi, 0) + raw.tobytes() + struct.pack('<I', raw_crc))
    segment_boxes = boxes
    if change == 'box':
        x, y, w, h = boxes[0]
        segment_boxes = [(x + 1, y, w, h)]
    encoded_boxes = bytes(v for b in segment_boxes for v in b) + bytes(256 - 4*len(boxes))
    asg = packet(b'ASG1', struct.pack('<4I', frame_id, 0, 1000, len(boxes)) + encoded_boxes)
    acrs = []
    chars = bytearray()
    for index, box in enumerate(boxes):
        norm = normalize_frame(raw, box, roi)[0]
        scores = integer_cnn.logits(norm, integer_cnn.load(ROOT / 'model'))[0]
        best = int(scores.argmax())
        ascii_value = b'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'[best]
        chars.append(ascii_value)
        if change == 'norm':
            norm = norm.copy(); norm[0, 0] ^= 1
        if change == 'score':
            scores = scores.copy(); scores[0] += 1
        if change == 'argmax':
            best = (best + 1) % 36
        body = struct.pack('<II4B', frame_id, index, *box) + norm.tobytes()
        body += struct.pack('<I36iIBB2x', 200, *scores.tolist(), 300, best, ascii_value)
        acrs.append(packet(b'ACR2', body))
    aer = packet(b'AER1', struct.pack('<7I', frame_id, int(change == 'status'), len(boxes), 500, 0, 2, 0) + chars + bytes(64 - len(chars)))
    packets = [aif, asg, *acrs, aer]
    if change == 'missing': packets.pop(1)
    if change == 'packet_crc': packets[0] = packets[0][:-1] + bytes([packets[0][-1] ^ 1])
    return b''.join(packets)


class ObserverTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(importlib.util.find_spec('observe_auto'), 'observer implementation is missing')
        import observe_auto
        self.observer = observe_auto
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)

    def run_wire(self, wire, frames=1):
        source = self.directory / 'input.bin'
        source.write_bytes(wire)
        out = self.directory / 'result'
        with contextlib.redirect_stdout(io.StringIO()):
            code = self.observer.main(['--wire', str(source), '--out', str(out), '--frames', str(frames)])
        return code, json.loads((out / 'summary.json').read_text()), out

    def test_blank_frame_is_verified_and_raw_is_saved(self):
        code, summary, out = self.run_wire(fixture())
        self.assertEqual(code, 0)
        self.assertEqual(summary['verified_frames'], 1)
        self.assertEqual(summary['verified_characters'], 0)
        np.testing.assert_array_equal(np.load(next(out.glob('frames/*/raw.npy'))), np.full((120, 160), 230, np.uint8))
        self.assertEqual((out / 'wire.bin').read_bytes(), fixture())

    def test_dynamic_roi_is_independently_checked(self):
        raw=bytes([97])*19200
        aif=packet(b'AIF1',struct.pack('<II4BB3x',1,100,0,0,160,120,0)+raw+struct.pack('<I',zlib.crc32(raw)))
        aer=packet(b'AER1',struct.pack('<7I',1,0,0,500,0,0,0)+bytes(64))
        for roi,ok in [((0,0,0,0),True),((26,41,150,76),False)]:
            with self.subTest(roi=roi),tempfile.TemporaryDirectory() as folder:
                self.directory=Path(folder)
                asg=packet(b'ASG2',struct.pack('<4I',1,0,1000,0)+bytes(roi)+bytes(256))
                code,summary,out=self.run_wire(aif+asg+aer)
                self.assertEqual(code==0,ok)
                if not ok:
                    row=json.loads(next(out.glob('frames/*/result.json')).read_text())
                    self.assertIn('located_roi_mismatch',row['errors'])

    def test_real_character_compares_all_reference_outputs(self):
        code, summary, out = self.run_wire(fixture(character=True))
        self.assertEqual(code, 0)
        self.assertEqual(summary['verified_characters'], 1)
        frame = json.loads(next(out.glob('frames/*/result.json')).read_text())
        self.assertTrue(frame['passed'])
        self.assertEqual(frame['characters'][0]['score_mismatches'], 0)
        self.assertEqual(frame['characters'][0]['norm_pixel_mismatches'], 0)

    def test_each_inference_mismatch_fails(self):
        for change in ['norm', 'score', 'argmax', 'box', 'status']:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as folder:
                self.directory = Path(folder)
                code, summary, _ = self.run_wire(fixture(character=True, change=change))
                self.assertNotEqual(code, 0)
                self.assertEqual(summary['verified_frames'], 0)

    def test_missing_and_corrupt_packets_never_pass(self):
        for change in ['missing', 'packet_crc', 'raw_crc']:
            with self.subTest(change=change), tempfile.TemporaryDirectory() as folder:
                self.directory = Path(folder)
                code, summary, _ = self.run_wire(fixture(change=change))
                self.assertNotEqual(code, 0)
                self.assertEqual(summary['verified_frames'], 0)
                self.assertGreater(summary['groups']['incomplete_groups'], 0)

    def test_pending_groups_are_bounded_and_reported(self):
        wire = b''.join(fixture(i, change='missing') for i in range(12)) + fixture(12)
        code, summary, _ = self.run_wire(wire)
        self.assertEqual(code, 0)
        self.assertEqual(summary['groups']['incomplete_groups'], 12)
        self.assertLessEqual(summary['groups']['peak_pending_groups'], 8)
        self.assertGreater(summary['groups']['evicted_groups'], 0)

    def test_epoch_reset_does_not_combine_old_partial_frame(self):
        wire = fixture(10, change='missing') + fixture(0)
        code, summary, _ = self.run_wire(wire)
        self.assertEqual(code, 0)
        self.assertEqual(summary['groups']['epochs'], 2)
        self.assertEqual(summary['groups']['incomplete_groups'], 1)

    def test_forbidden_port_is_rejected_before_open(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertRaises(SystemExit, self.observer.main, ['--port', 'COM15', '--out', str(self.directory / 'no')])

    def test_live_receive_closes_before_reference_and_never_writes(self):
        # 串口是唯一替身；真实解码、分组、参考模型和磁盘输出照常运行。
        import serial
        state = dict(closed=False, reads=0)
        data = fixture(character=True)
        class Source:
            def __enter__(self): return self
            def __exit__(self, *args): state['closed'] = True
            def read(self, count):
                state['reads'] += 1
                return data
            def write(self, *args):
                raise AssertionError('observer must never write to serial')
        real_verify = self.observer.verify_frame
        def checked_verify(*args):
            self.assertTrue(state['closed'], 'reference computation blocked the receiver')
            return real_verify(*args)
        with patch.object(serial, 'Serial', return_value=Source()), patch.object(self.observer, 'verify_frame', side_effect=checked_verify), contextlib.redirect_stdout(io.StringIO()):
            code = self.observer.main(['--out', str(self.directory / 'live'), '--frames', '1'])
        self.assertEqual(code, 0)
        self.assertEqual(state['reads'], 1)

    def test_insufficient_verified_count_fails(self):
        code, summary, _ = self.run_wire(fixture(), frames=2)
        self.assertNotEqual(code, 0)
        self.assertEqual(summary['verified_frames'], 1)

    def test_final_truncated_packet_is_reported(self):
        code, summary, _ = self.run_wire(fixture()[:-12])
        self.assertNotEqual(code, 0)
        self.assertEqual(summary['groups']['incomplete_groups'], 1)
        self.assertGreater(summary['parser']['truncated_bytes'], 0)

    def test_truth_is_scored_after_prediction_without_changing_it(self):
        source = self.directory / 'truth_input.bin'
        source.write_bytes(fixture(character=True))
        out = self.directory / 'truth_result'
        with contextlib.redirect_stdout(io.StringIO()):
            code = self.observer.main(['--wire', str(source), '--out', str(out), '--frames', '1', '--truth', 'WRONG'])
        self.assertEqual(code, 0)
        summary = json.loads((out / 'summary.json').read_text())
        frame = json.loads(next(out.glob('frames/*/result.json')).read_text())
        self.assertEqual(summary['truth_exact_frames'], 0)
        self.assertFalse(frame['truth_exact'])
        self.assertEqual(frame['hardware_prediction'], frame['reference_prediction'])


if __name__ == '__main__':
    unittest.main()
