"""采集边界回归：完整块留存、帧数上限与残包不能冒充完整帧。"""
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest

from auto_protocol import StreamParser
from test_observe_auto import fixture


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(importlib.util.find_spec('auto_capture'),
                             'independent capture module is missing')
        from auto_capture import capture_stream
        from auto_collect import FrameCollector
        self.capture_stream = capture_stream
        self.collector_type = FrameCollector
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)

    def capture(self, data, frames=1):
        source = self.directory / 'input.bin'
        source.write_bytes(data)
        out = self.directory / 'output'
        out.mkdir()
        collector = self.collector_type(out)
        parser = StreamParser()
        result = self.capture_stream(wire_path=source, out=out, port='COM10',
                                     baud=12_000_000, frames=frames, timeout=30,
                                     stream_parser=parser, collector=collector,
                                     started=time.monotonic())
        return result, collector, parser, out

    def test_frame_limit_preserves_full_read_block(self):
        first = fixture()
        data = first + fixture(2)
        result, collector, parser, out = self.capture(data)
        self.assertIsNone(result['capture_error'])
        self.assertFalse(result['timed_out'])
        self.assertEqual(collector.stats['complete_groups'], 1)
        # 第一帧长度不足五个4096字节块；块内后续字节仍必须落盘。
        self.assertEqual(result['bytes_received'], 20480)
        self.assertEqual((out / 'wire.bin').read_bytes(), data[:20480])
        self.assertEqual(len(collector.paths), 1)

    def test_truncation_never_becomes_complete_group(self):
        result, collector, parser, out = self.capture(fixture()[:-12])
        self.assertIsNone(result['capture_error'])
        self.assertEqual(collector.stats['complete_groups'], 0)
        self.assertEqual(collector.stats['incomplete_groups'], 1)
        self.assertGreater(parser.stats['truncated_bytes'], 0)
        rejection = json.loads((out / 'rejected_groups.jsonl').read_text())
        self.assertEqual(rejection['missing'], ['AER1'])


if __name__ == '__main__':
    unittest.main()
