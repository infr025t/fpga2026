import binascii
import contextlib
import csv
import importlib.util
import io
import json
import pathlib
import struct
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock


def packet(frame_id=7, payload=b'FPG1abcd', **changes):
    fields = dict(version=1, mode=1, width=4, height=2, threshold=180,
                  frame_id=frame_id, length=len(payload), bright_count=2,
                  sum_x=7, sum_y=5)
    fields.update(changes)
    h = b'FPG1' + struct.pack('<BBHHHIIIII', *fields.values())
    body = h[4:] + payload
    return h + payload + struct.pack('<H', binascii.crc_hqx(body, 0xffff))


def target_packet(frame_id=70, payload=None, base=None, **changes):
    fields = dict(version=2, mode=0, width=6, height=4, threshold=180,
                  frame_id=frame_id, length=24, bright_count=2, sum_x=7, sum_y=5)
    fields.update(base or {})
    if payload is None:
        payload = bytes(index & 0xff for index in range(fields['width'] * fields['height']))
    fields['length'] = len(payload)
    target = dict(flags=7, target_threshold=96,
                  roi_x_min=1, roi_y_min=1, roi_x_max=6, roi_y_max=4,
                  bbox_x_min=3, bbox_y_min=2, bbox_x_max=5, bbox_y_max=3,
                  target_area=6, target_sum_x=24, target_sum_y=15,
                  min_area=2, max_area=12, reserved=0)
    target.update(changes)
    header = b'FPG1' + struct.pack('<BBHHHIIIII', *fields.values())
    header += struct.pack('<BBHHHHHHHHIIIIIH', *target.values())
    return header + payload + struct.pack('<H', binascii.crc_hqx(header[4:] + payload, 0xffff))


EMPTY_TARGET = dict(target_area=0, target_sum_x=0, target_sum_y=0,
                    bbox_x_min=0, bbox_y_min=0, bbox_x_max=0, bbox_y_max=0)


def output_packet(frame_id=110, payload=None, transport=5, base=None, **changes):
    """Build wire-format v3 packets; target data remains independently packed."""
    fields = dict(version=3, mode=1, width=6, height=4)
    fields.update(base or {})
    if payload is None:
        size = fields['width'] * fields['height']
        payload = bytes((size + 7) // 8) if transport & 1 else b''
    wire = bytearray(target_packet(frame_id, payload, fields, **changes))
    if transport == 1:
        wire[32:70] = bytes(38)
    wire[70] = transport
    wire[-2:] = struct.pack('<H', binascii.crc_hqx(wire[4:-2], 0xffff))
    return bytes(wire)


def rewrite_wire(wire, offset, data):
    """Change a field while preserving a valid CRC to exercise validation."""
    wire = bytearray(wire)
    wire[offset:offset + len(data)] = data
    wire[-2:] = struct.pack('<H', binascii.crc_hqx(wire[4:-2], 0xffff))
    return bytes(wire)


class DisplayArray:
    """Tiny array stand-in that exposes unintended overlay writes in tests."""
    def __init__(self, pixels):
        self.pixels = pixels

    def reshape(self, height, width):
        assert len(self.pixels) == height * width
        return self


class DisplayNumpy:
    uint8 = object()

    def __init__(self):
        self.sources = []
        self.blanks = []

    def frombuffer(self, pixels, dtype):
        self.sources.append(bytes(pixels))
        return DisplayArray(pixels)

    def zeros(self, dimensions, dtype):
        self.blanks.append(dimensions)
        return DisplayArray(bytes(dimensions[0] * dimensions[1]))


class DisplayCv:
    COLOR_GRAY2BGR = 1
    FONT_HERSHEY_SIMPLEX = 2

    def __init__(self):
        self.texts = []
        self.circles = []
        self.shown = []
        self.closed = False

    def cvtColor(self, picture, conversion):
        return DisplayArray(bytearray(picture.pixels))

    def rectangle(self, picture, *args):
        picture.pixels[0] = 201

    def circle(self, picture, center, *args):
        self.circles.append(center)
        picture.pixels[0] = 202

    def putText(self, picture, label, *args):
        self.texts.append(label)
        picture.pixels[0] = 203

    def imshow(self, name, picture):
        self.shown.append(picture)

    def waitKey(self, duration):
        return -1

    def destroyAllWindows(self):
        self.closed = True


class ReceiverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path = pathlib.Path(__file__).with_name('receiver.py')
        if path.exists():
            spec = importlib.util.spec_from_file_location('receiver', path)
            cls.receiver = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cls.receiver)
        else:
            cls.receiver = None

    def parser(self):
        self.assertIsNotNone(self.receiver, 'receiver implementation is missing')
        return self.receiver.FrameParser()

    def run_mock_serial(self, reads, options=(), cv=None):
        """Exercise the real CLI loop without a serial port or wall-clock waits."""
        pending = iter(reads)
        clock = [0.0]
        saved = []

        class Stream:
            closed = False
            buffered = b''

            def __enter__(self):
                return self

            def __exit__(self, *args):
                self.closed = True

            def read(self, count):
                if self.buffered:
                    data, self.buffered = self.buffered[:count], self.buffered[count:]
                    return data
                try:
                    clock[0], data = next(pending)
                except StopIteration:
                    raise KeyboardInterrupt
                self.buffered = data[count:]
                return data[:count]

            @property
            def in_waiting(self):
                return len(self.buffered)

        stream = Stream()
        serial = types.SimpleNamespace(Serial=mock.Mock(return_value=stream))
        modules = {'serial': serial}
        if cv is not None:
            modules.update(cv2=cv, numpy=types.SimpleNamespace())

        def save(frame, out):
            saved.append((clock[0], frame['frame_id']))
            return pathlib.Path(f"frame_{frame['frame_id']}.json")

        output = io.StringIO()
        with (mock.patch.dict(sys.modules, modules),
              mock.patch.object(sys, 'argv', ['receiver.py', '--port', 'mock', *options]),
              mock.patch.object(self.receiver.time, 'monotonic', side_effect=lambda: clock[0]),
              mock.patch.object(self.receiver, 'save_frame', side_effect=save),
              contextlib.redirect_stdout(output)):
            self.receiver.main()
        serial.Serial.assert_called_once_with('mock', 1000000, timeout=0.25)
        self.assertTrue(stream.closed)
        return saved, output.getvalue()

    def test_fragmented_payload_magic_and_centroid(self):
        p = self.parser()
        frames = []
        for b in packet():
            frames.extend(p.feed(bytes([b])))
        self.assertEqual(len(frames), 1)
        self.assertEqual(frames[0]['pixels'], b'FPG1abcd')
        self.assertEqual(frames[0]['pixel_format'], 'gray8')
        self.assertEqual(frames[0]['centroid_x'], 3)
        self.assertEqual(frames[0]['centroid_y'], 2)

    def test_qvga_payload_streamed_in_irregular_chunks(self):
        p = self.parser()
        size = 318 * 238
        payload = (bytes(range(256)) * ((size + 255) // 256))[:size]
        wire = packet(101, payload, width=318, height=238) + packet(102)
        frames = []
        position = 0
        sizes = (1, 7, 31, 4096)
        index = 0
        while position < len(wire):
            length = sizes[index % len(sizes)]
            frames.extend(p.feed(wire[position:position + length]))
            position += length
            index += 1
        self.assertEqual([f['frame_id'] for f in frames], [101, 102])
        self.assertEqual(frames[0]['pixels'], payload)
        self.assertFalse(p.finish())

    def test_noise_bad_crc_and_invalid_headers_recover(self):
        p = self.parser()
        corrupt = bytearray(packet()); corrupt[-1] ^= 1
        noise = b'garbageFPG' + corrupt + packet(version=3) + packet(mode=2)
        noise += packet(width=0) + packet(length=99999999)
        frames = p.feed(noise + packet(8))
        self.assertEqual([f['frame_id'] for f in frames], [8])

    def test_truncated_frame_resync_only_to_verified_packet(self):
        p = self.parser()
        self.assertEqual(p.feed(packet(1, b'x' * 100, width=10, height=10)[:38]), [])
        self.assertEqual(p.feed(packet(9)), [])
        self.assertEqual([f['frame_id'] for f in p.feed(b'', boundary=True)], [9])
        self.assertFalse(p.finish())

    def test_embedded_complete_packets_do_not_change_any_two_chunk_split(self):
        for inner in (packet(22), target_packet(23), output_packet(24),
                      output_packet(25, transport=6)):
            payload = b'prefix' + inner + b'suffix' + bytes(50)
            outer = packet(21, payload, width=len(payload), height=1)
            for cut in range(1, len(outer)):
                with self.subTest(inner_version=inner[4], cut=cut):
                    p = self.parser()
                    frames = p.feed(outer[:cut]) + p.feed(outer[cut:])
                    self.assertEqual([frame['frame_id'] for frame in frames], [21])
                    self.assertEqual(frames[0]['pixels'], payload)
                    self.assertEqual(p.rejected, 0)
                    self.assertFalse(p.finish())
            p = self.parser()
            frames = []
            for value in outer:
                frames.extend(p.feed(bytes([value])))
            self.assertEqual([frame['frame_id'] for frame in frames], [21])

    def test_boundary_recovers_verified_packets_and_retains_incomplete_tail(self):
        bad = bytearray(packet(8))
        bad[-1] ^= 1
        old = packet(1, bytes(318 * 238), width=318, height=238)[:38]
        p = self.parser()
        wire = old + bad + packet(9) + output_packet(10, transport=6) + packet(11)[:20]
        self.assertEqual(p.feed(wire), [])
        frames = p.feed(b'', boundary=True)
        self.assertEqual([frame['frame_id'] for frame in frames], [9, 10])
        self.assertTrue(p.finish())
        self.assertEqual(p.rejected, 2)
        self.assertEqual([frame['frame_id'] for frame in p.feed(packet(12))], [12])

    def test_empty_centroid_and_file_outputs(self):
        p = self.parser()
        f = p.feed(packet(bright_count=0, sum_x=0, sum_y=0))[0]
        self.assertIsNone(f['centroid_x'])
        with tempfile.TemporaryDirectory() as d:
            self.receiver.save_frame(f, pathlib.Path(d))
            self.assertEqual(len(list(pathlib.Path(d).glob('*.pgm'))), 1)
            self.assertEqual(len(list(pathlib.Path(d).glob('*.json'))), 1)
            self.assertTrue((pathlib.Path(d) / 'metadata.csv').exists())

    def test_saving_preserves_orphaned_images_and_metadata(self):
        f = self.parser().feed(packet())[0]
        with tempfile.TemporaryDirectory() as d:
            out = pathlib.Path(d)
            orphan_meta = out / 'frame_0000000007.json'
            orphan_image = out / 'frame_0000000007_1.pgm'
            orphan_meta.write_text('original metadata', encoding='utf-8')
            orphan_image.write_bytes(b'original image')
            image = self.receiver.save_frame(f, out)
            self.assertEqual(image.name, 'frame_0000000007_2.pgm')
            self.assertEqual(orphan_meta.read_text(encoding='utf-8'), 'original metadata')
            self.assertEqual(orphan_image.read_bytes(), b'original image')
            self.assertEqual(image.read_bytes(), b'P5\n4 2\n255\n' + f['pixels'])
            meta = json.loads(image.with_suffix('.json').read_text(encoding='utf-8'))
            self.assertEqual(meta['image_file'], image.name)
            second = self.receiver.save_frame(f, out)
            self.assertEqual(second.name, 'frame_0000000007_3.pgm')

    def test_finish_reports_only_unfinished_packets_and_resets(self):
        p = self.parser()
        self.assertEqual(p.feed(packet()[:35]), [])
        self.assertTrue(p.finish())
        self.assertEqual(p.rejected, 1)
        self.assertFalse(p.finish())
        self.assertEqual([f['frame_id'] for f in p.feed(packet(8))], [8])
        self.assertFalse(p.finish())
        self.assertEqual(p.feed(b'noise ending in FPG'), [])
        self.assertFalse(p.finish())
        self.assertEqual(p.rejected, 1)

    def test_recorded_input_reports_truncation_without_losing_valid_frames(self):
        script = pathlib.Path(__file__).with_name('receiver.py')
        cases = [
            (packet() + packet(8)[:20], [], 1, 'incomplete frame'),
            (packet() + b'noiseFPG', [], 0, ''),
            (packet() + packet(8)[:20], ['--count', '1'], 0, ''),
            (packet() + packet(8)[:20], ['--count', '2'], 1, 'requested frame count'),
        ]
        for wire, options, exit_code, error in cases:
            with self.subTest(options=options, wire_tail=wire[-8:]):
                with tempfile.TemporaryDirectory() as d:
                    root = pathlib.Path(d)
                    recorded = root / 'wire.bin'
                    recorded.write_bytes(wire)
                    result = subprocess.run(
                        [sys.executable, str(script), '--input', str(recorded),
                         '--out', str(root / 'frames'), *options],
                        capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, exit_code, result.stderr)
                    if error:
                        self.assertIn(error, result.stderr)
                    else:
                        self.assertEqual(result.stderr, '')
                    self.assertEqual(len(list((root / 'frames').glob('*.pgm'))), 1)

    def test_recorded_eof_recovers_short_packets_after_large_truncated_frame(self):
        script = pathlib.Path(__file__).with_name('receiver.py')
        old = packet(1, bytes(318 * 238), width=318, height=238)[:38]
        recovered = packet(31) + target_packet(32) + output_packet(33, transport=6)
        cases = [(b'', [], 0, ''),
                 (packet(34)[:20], [], 1, 'incomplete frame'),
                 (packet(34)[:20], ['--count', '3'], 0, ''),
                 (b'', ['--count', '4'], 1, 'requested frame count')]
        for tail, options, exit_code, error in cases:
            with self.subTest(options=options, tail=bool(tail)):
                with tempfile.TemporaryDirectory() as d:
                    root = pathlib.Path(d)
                    recorded = root / 'wire.bin'
                    recorded.write_bytes(old + recovered + tail)
                    result = subprocess.run(
                        [sys.executable, str(script), '--input', str(recorded),
                         '--out', str(root / 'frames'), *options],
                        capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, exit_code, result.stderr)
                    self.assertIn('Received 3 valid frames;', result.stdout)
                    self.assertEqual(len(list((root / 'frames').glob('*.json'))), 3)
                    self.assertEqual(len(list((root / 'frames').glob('*.pgm'))), 2)
                    if error:
                        self.assertIn(error, result.stderr)
                    else:
                        self.assertEqual(result.stderr, '')

    def test_serial_idle_recovery_waits_for_continuous_no_byte_interval(self):
        old = packet(1, bytes(100), width=10, height=10)[:38]
        saved, output = self.run_mock_serial(
            [(0.1, old + packet(9)), (0.35, b''), (0.85, b''),
             (0.95, b'x'), (1.5, b''), (2.0, b'')], ['--count', '1'])
        self.assertEqual(saved, [(2.0, 9)])
        self.assertIn('rejected/resynchronized 1 candidates', output)

    def test_serial_idle_recovery_can_be_disabled(self):
        old = packet(1, bytes(100), width=10, height=10)[:38]
        saved, output = self.run_mock_serial(
            [(0.1, old + packet(9)), (0.35, b''), (100.0, b'')],
            ['--idle-resync', '0'])
        self.assertEqual(saved, [])
        self.assertIn('Received 0 valid frames;', output)
        self.assertIn('rejected/resynchronized 0 candidates', output)

    def test_serial_idle_boundary_discards_late_remainder_of_old_frame(self):
        old = packet(1, bytes(100), width=10, height=10)
        saved, output = self.run_mock_serial(
            [(0.1, old[:38]), (0.35, b''), (1.2, b''),
             (1.3, old[38:] + packet(9))], ['--count', '1'])
        self.assertEqual(saved, [(1.3, 9)])
        self.assertIn('rejected/resynchronized 1 candidates', output)

    def test_serial_preview_handles_quit_while_no_frames_arrive(self):
        cv = types.SimpleNamespace(waitKey=mock.Mock(return_value=ord('q')),
                                   destroyAllWindows=mock.Mock())
        saved, _ = self.run_mock_serial([(0.25, b'')], ['--display'], cv)
        self.assertEqual(saved, [])
        cv.waitKey.assert_called_once_with(1)
        cv.destroyAllWindows.assert_called_once_with()

    def test_invalid_idle_resync_fails_before_importing_serial(self):
        script = pathlib.Path(__file__).with_name('receiver.py')
        for duration in ('-0.1', 'nan', 'inf'):
            with self.subTest(duration=duration):
                result = subprocess.run(
                    [sys.executable, str(script), '--port', 'unused',
                     '--idle-resync', duration], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertIn('--idle-resync must be a finite nonnegative number', result.stderr)
                self.assertNotIn('Traceback', result.stderr)

    def test_invalid_baud_fails_before_importing_serial(self):
        script = pathlib.Path(__file__).with_name('receiver.py')
        result = subprocess.run(
            [sys.executable, str(script), '--port', 'unused', '--baud', '0'],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn('--baud must be positive', result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def test_serial_short_packet_is_read_without_waiting_to_fill_large_buffer(self):
        wire = output_packet(190, transport=6)

        class SerialBuffer:
            def __init__(self, data):
                self.data = data
                self.read_sizes = []
                self.timeouts = 0

            @property
            def in_waiting(self):
                return len(self.data)

            def read(self, size):
                self.read_sizes.append(size)
                if len(self.data) < size:
                    self.timeouts += 1
                chunk, self.data = self.data[:size], self.data[size:]
                return chunk

        stream = SerialBuffer(wire)
        chunk = self.receiver.read_serial_chunk(stream)
        self.assertEqual([f['frame_id'] for f in self.parser().feed(chunk)], [190])
        self.assertEqual(stream.read_sizes, [1, 73])
        self.assertEqual(stream.timeouts, 0)
        # Large bursts remain bounded and preserve all bytes across calls.
        data = bytes(range(256)) * 20
        stream = SerialBuffer(data)
        first = self.receiver.read_serial_chunk(stream)
        second = self.receiver.read_serial_chunk(stream)
        self.assertEqual(len(first), 4096)
        self.assertEqual(first + second, data)
        self.assertEqual(stream.timeouts, 0)
        self.assertEqual(self.receiver.read_serial_chunk(stream), b'')
        self.assertEqual(stream.timeouts, 1)

    def test_hold_preview_requires_display_before_optional_imports(self):
        script = pathlib.Path(__file__).with_name('receiver.py')
        result = subprocess.run(
            [sys.executable, str(script), '--port', 'unused', '--hold-preview'],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn('--hold-preview requires --display', result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def test_serial_cli_emits_short_features_packet_before_read_timeout(self):
        class ShortPacketPort:
            def __init__(self):
                self.buffer = output_packet(191, transport=6)
                self.elapsed = 0.00074
                self.closed = False

            def __enter__(self):
                return self

            def __exit__(self, *args):
                self.closed = True

            @property
            def in_waiting(self):
                return len(self.buffer)

            def read(self, count):
                # pyserial waits for requested bytes or timeout, including when
                # fewer than count bytes already make a complete protocol frame.
                if len(self.buffer) < count:
                    self.elapsed += 0.25
                data, self.buffer = self.buffer[:count], self.buffer[count:]
                return data

        stream = ShortPacketPort()
        serial = types.SimpleNamespace(Serial=mock.Mock(return_value=stream))
        saves = []

        def save(frame, out):
            saves.append((frame['frame_id'], stream.elapsed))
            return pathlib.Path('features.json')

        with (mock.patch.dict(sys.modules, {'serial': serial}),
              mock.patch.object(sys, 'argv', ['receiver.py', '--port', 'mock', '--count', '1']),
              mock.patch.object(self.receiver, 'save_frame', side_effect=save),
              mock.patch.object(self.receiver.time, 'monotonic', side_effect=lambda: stream.elapsed),
              contextlib.redirect_stdout(io.StringIO())):
            self.receiver.main()
        self.assertEqual(saves, [(191, 0.00074)])
        self.assertTrue(stream.closed)

    def test_held_preview_mixes_raw_and_packed_with_current_target_geometry(self):
        frames = self.parser().feed(
            target_packet(200, base=dict(mode=1))
            + output_packet(201, transport=6, bbox_x_min=4, bbox_x_max=5,
                            bbox_y_min=3, bbox_y_max=3, target_area=2,
                            target_sum_x=9, target_sum_y=6)
            + output_packet(202, payload=b'\x81\x00\x03')
            + output_packet(203, transport=6))
        originals = [frame['pixels'] for frame in frames]
        cache = self.receiver.PreviewCache()
        cv, np = DisplayCv(), DisplayNumpy()
        displays = [cache.render(frame, cv, np) for frame in frames]
        self.assertEqual(np.sources, [originals[0], originals[0], originals[2], originals[2]])
        self.assertEqual(np.blanks, [])
        self.assertEqual(cv.circles, [(3, 1), (3, 2), (3, 1), (3, 1)])
        self.assertIn('Preview frame=200 (held)', cv.texts)
        self.assertIn('Target frame=201', cv.texts)
        self.assertIn('Preview frame=202 (held)', cv.texts)
        self.assertIn('Target frame=203', cv.texts)
        # Drawing really mutates the stand-in display; source/cache bytes do not.
        self.assertTrue(all(picture.pixels[0] == 203 for picture in displays))
        self.assertEqual([frame['pixels'] for frame in frames], originals)
        self.assertEqual(cache.pixels, originals[2])
        self.assertTrue(all('image_file' not in frame for frame in frames))

    def test_held_preview_without_image_uses_blank_canvas(self):
        cache = self.receiver.PreviewCache()
        cv, np = DisplayCv(), DisplayNumpy()
        frame = self.parser().feed(output_packet(1, transport=6))[0]
        cache.render(frame, cv, np)
        self.assertEqual(np.blanks, [(4, 6)])
        self.assertEqual(np.sources, [])
        self.assertEqual(cv.texts, ['Features only - Target sensor=(4,2)'])

    def test_held_preview_discards_incompatible_and_reset_frames_until_new_image(self):
        cases = [dict(frame_id=19), dict(frame_id=21), dict(frame_id=0),
                 dict(frame_id=22, base=dict(mode=0)),
                 dict(frame_id=22, base=dict(width=7)),
                 dict(frame_id=22, base=dict(height=5)),
                 dict(frame_id=22, base=dict(threshold=181))]
        for changes in cases:
            with self.subTest(changes=changes):
                cache = self.receiver.PreviewCache()
                cv, np = DisplayCv(), DisplayNumpy()
                first, held = self.parser().feed(
                    output_packet(20) + output_packet(21, transport=6))
                cache.render(first, cv, np)
                cache.render(held, cv, np)
                incompatible = self.parser().feed(output_packet(transport=6, **changes))[0]
                cache.render(incompatible, cv, np)
                # Returning to the old settings must not resurrect an old image.
                later = self.parser().feed(output_packet(30, transport=6))[0]
                cache.render(later, cv, np)
                self.assertIsNone(cache.pixels)
                self.assertEqual(len(np.blanks), 2)
                self.assertEqual(len(np.sources), 2)
                fresh, latest = self.parser().feed(
                    output_packet(31, payload=b'\xff\x01\x00')
                    + output_packet(32, transport=6))
                cache.render(fresh, cv, np)
                cache.render(latest, cv, np)
                self.assertEqual(cache.pixels, fresh['pixels'])
                self.assertIn('Preview frame=31 (held)', cv.texts)
                self.assertIn('Target frame=32', cv.texts)

    def test_held_preview_cli_keeps_features_metadata_and_saved_images_separate(self):
        wires = [target_packet(300, base=dict(mode=1)),
                 output_packet(301, transport=6), output_packet(302),
                 output_packet(303, transport=6, flags=6, **EMPTY_TARGET)]
        expected = self.parser().feed(b''.join(wires))
        cv, np = DisplayCv(), DisplayNumpy()
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            recorded = root / 'wire.bin'
            recorded.write_bytes(b''.join(wires))
            out = root / 'frames'
            argv = ['receiver.py', '--input', str(recorded), '--out', str(out),
                    '--display', '--hold-preview']
            with (mock.patch.dict(sys.modules, {'cv2': cv, 'numpy': np}),
                  mock.patch.object(sys, 'argv', argv),
                  contextlib.redirect_stdout(io.StringIO())):
                self.receiver.main()
            self.assertTrue(cv.closed)
            self.assertEqual(len(cv.shown), 4)
            self.assertEqual(len(list(out.glob('*.pgm'))), 2)
            self.assertEqual(len(list(out.glob('*.json'))), 4)
            for frame in expected:
                stem = f"frame_{frame['frame_id']:010d}"
                meta = json.loads((out / (stem + '.json')).read_text(encoding='utf-8'))
                self.assertEqual(meta['target'], frame['target'])
                if frame['pixel_format'] == 'none':
                    self.assertIsNone(meta['image_file'])
                    self.assertFalse((out / (stem + '.pgm')).exists())
                else:
                    self.assertEqual((out / (stem + '.pgm')).read_bytes(),
                                     b'P5\n6 4\n255\n' + frame['pixels'])
            self.assertIn('Preview frame=300 (held)', cv.texts)
            self.assertIn('Target frame=301', cv.texts)
            self.assertIn('Preview frame=302 (held)', cv.texts)
            self.assertIn('Target frame=303', cv.texts)

    def test_noise_is_bounded_and_complete_frames_take_precedence(self):
        p = self.parser()
        self.assertEqual(p.feed(b'x' * 1000000), [])
        self.assertLessEqual(len(p.buffer), 3)
        embedded = packet(22)
        outer = packet(21, embedded, width=len(embedded), height=1)
        frames = p.feed(outer + packet(23))
        self.assertEqual([f['frame_id'] for f in frames], [21, 23])
        self.assertEqual(frames[0]['pixels'], embedded)

    def test_bad_dimensions_statistics_and_threshold_recover(self):
        p = self.parser()
        malformed = (packet(width=319) + packet(height=239)
                     + packet(threshold=2048) + packet(bright_count=9)
                     + packet(sum_x=9999) + packet(sum_y=9999))
        self.assertEqual([f['frame_id'] for f in p.feed(malformed + packet(25))], [25])

    def test_v2_fragmentation_preserves_legacy_statistics_and_payload(self):
        p = self.parser()
        payload = b'FPG1' + bytes(range(20))
        wire = target_packet(payload=payload)
        self.assertEqual(self.receiver.TARGET_EXTENSION.size, 40)
        self.assertEqual(len(wire), 72 + len(payload) + 2)
        frames = []
        for value in wire:
            frames.extend(p.feed(bytes([value])))
        self.assertEqual(len(frames), 1)
        frame = frames[0]
        self.assertEqual(frame['version'], 2)
        self.assertEqual(frame['pixel_format'], 'gray8')
        self.assertEqual(frame['pixels'], payload)
        self.assertEqual((frame['bright_count'], frame['centroid_x'], frame['centroid_y']), (2, 3, 2))
        target = frame['target']
        self.assertEqual((target['area'], target['sum_x'], target['sum_y']), (6, 24, 15))
        self.assertTrue(target['config_valid'])
        self.assertTrue(target['valid'])
        self.assertTrue(target['dark'])
        self.assertEqual(target['threshold'], 96)
        self.assertEqual(target['roi'], dict(x_min=1, y_min=1, x_max=6, y_max=4))
        self.assertEqual(target['bbox'], dict(x_min=3, y_min=2, x_max=5, y_max=3))
        self.assertEqual((target['centroid_x'], target['centroid_y']), (4, 2))
        self.assertFalse(p.finish())

    def test_v2_empty_filtered_and_invalid_config_have_no_target_geometry(self):
        wires = [target_packet(71, flags=6, **EMPTY_TARGET),
                 target_packet(72, flags=6, min_area=7),
                 target_packet(73, flags=6, max_area=5),
                 target_packet(74, flags=2, roi_x_min=0, **EMPTY_TARGET),
                 target_packet(75, flags=4, **EMPTY_TARGET)]
        frames = self.parser().feed(b''.join(wires))
        self.assertEqual([f['frame_id'] for f in frames], [71, 72, 73, 74, 75])
        for frame in frames:
            target = frame['target']
            self.assertFalse(target['valid'])
            self.assertIsNone(target['bbox'])
            self.assertIsNone(target['centroid_x'])
            self.assertIsNone(target['centroid_y'])
            geometry = self.receiver.display_geometry(frame)
            self.assertIsNone(geometry['bbox'])
            self.assertIsNone(geometry['centroid'])
        self.assertEqual(frames[1]['target']['area'], 6)
        self.assertEqual(frames[1]['target']['sum_x'], 24)
        self.assertEqual(frames[1]['target']['sum_y'], 15)
        self.assertFalse(frames[3]['target']['config_valid'])
        self.assertIsNone(self.receiver.display_geometry(frames[3])['roi'])
        self.assertFalse(frames[4]['target']['dark'])

    def test_v2_bright_single_pixel_and_full_roi_area_boundaries(self):
        wire = target_packet(
            83, flags=5, target_threshold=255, min_area=1, max_area=1,
            bbox_x_min=6, bbox_y_min=4, bbox_x_max=6, bbox_y_max=4,
            target_area=1, target_sum_x=6, target_sum_y=4)
        wire += target_packet(
            84, target_threshold=0, min_area=24, max_area=24,
            bbox_x_min=1, bbox_y_min=1, bbox_x_max=6, bbox_y_max=4,
            target_area=24, target_sum_x=84, target_sum_y=60)
        frames = self.parser().feed(wire)
        self.assertEqual([f['frame_id'] for f in frames], [83, 84])
        self.assertTrue(all(f['target']['valid'] for f in frames))
        self.assertFalse(frames[0]['target']['dark'])
        self.assertEqual(self.receiver.display_geometry(frames[0])['centroid'], (5, 3))
        self.assertEqual(frames[1]['target']['area'], 24)

    def test_v2_accepts_every_realizable_target_in_a_three_by_three_roi(self):
        # Enumerate actual sets of distinct pixels, independently of sum bounds.
        # This guards against rejecting legitimate sparse or filled target boxes.
        wires = []
        for mask in range(1, 1 << 9):
            points = [(index % 3 + 1, index // 3 + 1)
                      for index in range(9) if mask & (1 << index)]
            xs, ys = zip(*points)
            wires.append(target_packet(
                mask, base=dict(width=3, height=3, mode=1),
                roi_x_max=3, roi_y_max=3, min_area=1, max_area=9,
                bbox_x_min=min(xs), bbox_y_min=min(ys),
                bbox_x_max=max(xs), bbox_y_max=max(ys),
                target_area=len(points), target_sum_x=sum(xs), target_sum_y=sum(ys)))
        p = self.parser()
        frames = p.feed(b''.join(wires))
        self.assertEqual([f['frame_id'] for f in frames], list(range(1, 1 << 9)))
        self.assertEqual(p.rejected, 0)

    def test_v2_rejects_inconsistent_flags_configuration_and_statistics(self):
        malformed = [
            dict(flags=15), dict(reserved=1), dict(flags=3), dict(flags=2),
            dict(roi_x_min=0), dict(roi_y_min=0), dict(roi_x_max=7), dict(roi_y_max=5),
            dict(roi_x_min=5, roi_x_max=4), dict(roi_y_min=4, roi_y_max=3),
            dict(min_area=0), dict(min_area=13), dict(max_area=25),
            dict(flags=6), dict(flags=7, min_area=7), dict(flags=7, max_area=5),
            dict(flags=2, roi_x_min=0),
            dict(flags=3, roi_x_min=0, **EMPTY_TARGET),
            dict(flags=7, **EMPTY_TARGET),
            dict(flags=6, **{**EMPTY_TARGET, 'target_sum_x': 1}),
            dict(flags=6, **{**EMPTY_TARGET, 'bbox_x_min': 1}),
            dict(bbox_x_min=0), dict(bbox_y_min=0),
            dict(bbox_x_max=7), dict(bbox_y_max=5),
            dict(roi_x_min=4), dict(roi_y_min=3),
            dict(bbox_x_min=5, bbox_x_max=3), dict(bbox_y_min=3, bbox_y_max=2),
            dict(target_area=7), dict(target_sum_x=0), dict(target_sum_y=0),
            dict(target_sum_x=23), dict(target_sum_y=14),
            dict(target_sum_x=31), dict(target_sum_y=19),
            dict(target_area=1, target_sum_x=3, target_sum_y=2, min_area=1),
            dict(target_area=2, target_sum_x=6, target_sum_y=4),
        ]
        for changes in malformed:
            with self.subTest(changes=changes):
                p = self.parser()
                frames = p.feed(b'noiseFPG' + target_packet(**changes) + target_packet(99) + packet(100))
                self.assertEqual([f['frame_id'] for f in frames], [99, 100])
                self.assertGreaterEqual(p.rejected, 1)

    def test_v2_crc_covers_extension_and_recovers_after_header_or_payload_truncation(self):
        bad = bytearray(target_packet())
        bad[33] ^= 1
        p = self.parser()
        frames = p.feed(bytes(bad) + target_packet(76) + packet(77))
        self.assertEqual([f['frame_id'] for f in frames], [76, 77])
        for length in (35, 71, 72, 80, len(target_packet()) - 1):
            with self.subTest(length=length):
                p = self.parser()
                self.assertEqual(p.feed(target_packet()[:length]), [])
                self.assertTrue(p.finish())
                p = self.parser()
                frames = p.feed(target_packet()[:length] + b'noiseFPG' + target_packet(78))
                self.assertEqual([f['frame_id'] for f in frames], [78])

    def test_v2_qvga_and_mixed_frames_in_irregular_chunks(self):
        p = self.parser()
        large = target_packet(80, base=dict(width=318, height=238))
        wire = packet(79) + large + target_packet(81) + packet(82)
        frames = []
        index = 0
        for length in (1, 31, 40, 4096):
            frames.extend(p.feed(wire[index:index + length]))
            index += length
        while index < len(wire):
            frames.extend(p.feed(wire[index:index + 997]))
            index += 997
        self.assertEqual([f['frame_id'] for f in frames], [79, 80, 81, 82])
        self.assertEqual(len(frames[1]['pixels']), 318 * 238)
        self.assertNotIn('target', frames[0])
        self.assertNotIn('target', frames[-1])
        self.assertFalse(p.finish())

    def test_display_maps_sensor_coordinates_and_draws_on_a_copy(self):
        frame = self.parser().feed(target_packet(
            base=dict(width=14, height=10), roi_x_max=14, roi_y_max=10,
            bbox_x_min=4, bbox_y_min=3, bbox_x_max=7, bbox_y_max=8,
            target_area=24, target_sum_x=132, target_sum_y=132, max_area=70))[0]
        geometry = self.receiver.display_geometry(frame)
        self.assertEqual(geometry['roi'], ((0, 0), (13, 9)))
        self.assertEqual(geometry['bbox'], ((3, 2), (6, 7)))
        self.assertEqual(geometry['centroid'], (4, 4))
        self.assertIsNone(self.receiver.display_geometry(self.parser().feed(packet())[0]))

        class FakeCv:
            COLOR_GRAY2BGR = 1
            FONT_HERSHEY_SIMPLEX = 2

            def __init__(self):
                self.calls = []
                self.display = object()

            def cvtColor(self, original, conversion):
                self.calls.append(('copy', original, conversion))
                return self.display

            def rectangle(self, *args):
                self.calls.append(('rectangle', *args))

            def circle(self, *args):
                self.calls.append(('circle', *args))

            def putText(self, *args):
                self.calls.append(('text', *args))

        cv = FakeCv()
        original = object()
        pixels = frame['pixels']
        displayed = self.receiver.draw_target_overlay(original, frame, cv)
        self.assertIs(displayed, cv.display)
        self.assertEqual(frame['pixels'], pixels)
        self.assertTrue(any(call[0] == 'circle' and call[2] == (4, 4) for call in cv.calls))
        for call in cv.calls[1:]:
            self.assertIs(call[1], cv.display)
        missing = self.parser().feed(target_packet(flags=6, **EMPTY_TARGET))[0]
        cv = FakeCv()
        self.receiver.draw_target_overlay(original, missing, cv)
        self.assertFalse(any(call[0] == 'circle' for call in cv.calls))
        self.assertTrue(any(call[0] == 'text' and call[2] == 'No target' for call in cv.calls))

    def test_csv_flattens_mixed_versions_and_json_retains_target(self):
        frames = self.parser().feed(packet(90) + target_packet(91) + target_packet(92, flags=6, **EMPTY_TARGET) + packet(93))
        with tempfile.TemporaryDirectory() as d:
            out = pathlib.Path(d)
            paths = [self.receiver.save_frame(frame, out) for frame in frames]
            with (out / 'metadata.csv').open(newline='', encoding='utf-8') as handle:
                reader = csv.DictReader(handle)
                rows = list(reader)
                self.assertEqual(reader.fieldnames, list(self.receiver.CSV_FIELDS))
            self.assertEqual([row['version'] for row in rows], ['1', '2', '2', '1'])
            self.assertEqual(rows[0]['target_valid'], '')
            self.assertEqual(rows[1]['target_valid'], 'True')
            self.assertEqual(rows[1]['target_centroid_x'], '4')
            self.assertEqual(rows[1]['centroid_x'], '3')
            self.assertEqual(rows[1]['target_bbox_x_min'], '3')
            self.assertEqual(rows[2]['target_valid'], 'False')
            self.assertEqual(rows[2]['target_bbox_x_min'], '')
            self.assertEqual(rows[2]['target_centroid_x'], '')
            self.assertNotIn('target', rows[1])
            self.assertTrue(all(None not in row for row in rows))
            meta = json.loads(paths[1].with_suffix('.json').read_text(encoding='utf-8'))
            self.assertEqual(meta['target'], frames[1]['target'])
            self.assertEqual(paths[1].read_bytes(), b'P5\n6 4\n255\n' + frames[1]['pixels'])

    def test_csv_preserves_old_header_and_uses_versioned_schema(self):
        frames = self.parser().feed(target_packet(94) + packet(95))
        with tempfile.TemporaryDirectory() as d:
            out = pathlib.Path(d)
            old_csv = b'version,frame_id,centroid_x\r\n1,5,8\r\n'
            (out / 'metadata.csv').write_bytes(old_csv)
            for frame in frames:
                self.receiver.save_frame(frame, out)
            self.assertEqual((out / 'metadata.csv').read_bytes(), old_csv)
            with (out / 'metadata_v3.csv').open(newline='', encoding='utf-8') as handle:
                reader = csv.DictReader(handle)
                rows = list(reader)
                self.assertEqual(reader.fieldnames, list(self.receiver.CSV_FIELDS))
            self.assertEqual([row['version'] for row in rows], ['2', '1'])
            self.assertEqual(rows[1]['target_roi_x_min'], '')
            (out / 'metadata_v3.csv').write_bytes(b'unrelated,header\n')
            self.receiver.save_frame(frames[0], out)
            self.assertEqual((out / 'metadata_v3.csv').read_bytes(), b'unrelated,header\n')
            self.assertTrue((out / 'metadata_v3_1.csv').exists())

    def test_csv_preserves_foreign_encoding_and_unparseable_headers(self):
        frame = self.parser().feed(packet())[0]
        foreign = ('unrelated,header\n'.encode('utf-16'), b'bad,\xffheader\n',
                   b'x' * (csv.field_size_limit() + 1) + b'\n')
        for original in foreign:
            with self.subTest(prefix=original[:16]):
                with tempfile.TemporaryDirectory() as d:
                    out = pathlib.Path(d)
                    (out / 'metadata.csv').write_bytes(original)
                    (out / 'metadata_v3.csv').write_bytes(original)
                    self.receiver.save_frame(frame, out)
                    self.assertEqual((out / 'metadata.csv').read_bytes(), original)
                    self.assertEqual((out / 'metadata_v3.csv').read_bytes(), original)
                    with (out / 'metadata_v3_1.csv').open(newline='', encoding='utf-8') as handle:
                        reader = csv.DictReader(handle)
                        rows = list(reader)
                        self.assertEqual(reader.fieldnames, list(self.receiver.CSV_FIELDS))
                    self.assertEqual([row['frame_id'] for row in rows], ['7'])

    def test_v3_all_three_by_three_binary_patterns_fragmented(self):
        p = self.parser()
        frames = []
        wire = b''.join(output_packet(mask, mask.to_bytes(2, 'little'), 1,
                                     dict(width=3, height=3))
                        for mask in range(512))
        for index in range(0, len(wire), 13):
            frames.extend(p.feed(wire[index:index + 13]))
        self.assertEqual([f['frame_id'] for f in frames], list(range(512)))
        for mask, frame in enumerate(frames):
            self.assertEqual(frame['pixels'], bytes(255 if mask & (1 << bit) else 0
                                                    for bit in range(9)))
            self.assertEqual(frame['payload_length'], 2)
            self.assertEqual(frame['pixel_format'], 'mono1')
            self.assertNotIn('target', frame)
        self.assertEqual(p.rejected, 0)
        self.assertFalse(p.finish())

    def test_v3_non_byte_width_uses_continuous_lsb_first_pixels(self):
        frame = self.parser().feed(output_packet(
            payload=b'\x91\x41', transport=1, base=dict(width=5, height=3)))[0]
        self.assertEqual([i for i, value in enumerate(frame['pixels']) if value],
                         [0, 4, 7, 8, 14])
        self.assertEqual(len(frame['pixels']), 15)
        # The legacy bright count counts source pixels, not packed wire bytes.
        frame = self.parser().feed(output_packet(
            payload=b'\xff\x01', transport=1,
            base=dict(width=3, height=3, bright_count=9, sum_x=18, sum_y=18)))[0]
        self.assertEqual(frame['bright_count'], 9)
        self.assertEqual((frame['centroid_x'], frame['centroid_y']), (2, 2))

    def test_v3_packed_maximum_qvga_and_mixed_versions(self):
        size = 318 * 238
        payload = bytearray((index * 37) & 0xff for index in range((size + 7) // 8))
        payload[-1] &= (1 << (size % 8)) - 1
        wires = [packet(120), target_packet(121),
                 output_packet(122, bytes(payload), 1, dict(width=318, height=238)),
                 output_packet(123, transport=6), output_packet(124), packet(125)]
        p = self.parser()
        frames = []
        wire = b''.join(wires)
        offset = 0
        sizes = (1, 31, 40, 997, 4096)
        while offset < len(wire):
            count = sizes[offset % len(sizes)]
            frames.extend(p.feed(wire[offset:offset + count]))
            offset += count
        self.assertEqual([f['frame_id'] for f in frames], list(range(120, 126)))
        self.assertEqual([f['pixel_format'] for f in frames],
                         ['gray8', 'gray8', 'mono1', 'none', 'mono1', 'gray8'])
        self.assertEqual(frames[2]['pixels'], bytes(
            255 if payload[index // 8] & (1 << (index % 8)) else 0
            for index in range(size)))
        self.assertEqual(frames[2]['payload_length'], (size + 7) // 8)
        self.assertEqual(frames[3]['pixels'], b'')
        self.assertEqual(p.rejected, 0)
        self.assertFalse(p.finish())

    def test_v3_target_and_result_only_keep_target_geometry(self):
        frames = self.parser().feed(output_packet(130) + output_packet(131, transport=6)
                                    + output_packet(132, transport=6, base=dict(mode=0)))
        self.assertEqual([f['frame_id'] for f in frames], [130, 131, 132])
        for frame in frames:
            self.assertTrue(frame['target']['valid'])
            self.assertEqual(frame['target']['bbox'], dict(x_min=3, y_min=2, x_max=5, y_max=3))
            self.assertEqual(self.receiver.display_geometry(frame),
                             dict(roi=((0, 0), (5, 3)), bbox=((2, 1), (4, 2)),
                                  centroid=(3, 1), status='Target'))
        for frame in frames[1:]:
            self.assertEqual(frame['pixels'], b'')
            self.assertEqual(frame['pixel_format'], 'none')
            self.assertEqual(frame['payload_length'], 0)

    def test_v3_rejects_illegal_transport_reserved_mode_and_lengths(self):
        malformed = [output_packet(transport=flag) for flag in (0, 2, 3, 4, 7, 8, 255)]
        malformed += [rewrite_wire(output_packet(), 71, b'\x01'),
                      output_packet(base=dict(mode=0)),
                      output_packet(transport=1, base=dict(mode=0)),
                      output_packet(payload=b'\x00'),
                      output_packet(payload=bytes(4)),
                      output_packet(transport=6, payload=b'\x00'),
                      rewrite_wire(output_packet(), 16, struct.pack('<I', 99999999)),
                      rewrite_wire(output_packet(transport=1), 32, b'\x04'),
                      rewrite_wire(output_packet(transport=1), 69, b'\x01')]
        for wire in malformed:
            with self.subTest(header=wire[:72]):
                p = self.parser()
                self.assertEqual([f['frame_id'] for f in p.feed(wire + output_packet(140))], [140])
                self.assertGreaterEqual(p.rejected, 1)

    def test_v3_rejects_nonzero_padding_and_accepts_exact_byte_counts(self):
        malformed = [output_packet(payload=b'\x00\x02', transport=1,
                                   base=dict(width=3, height=3)),
                     output_packet(payload=b'\x00\x80', transport=1,
                                   base=dict(width=5, height=3))]
        p = self.parser()
        frames = p.feed(b''.join(malformed) + output_packet(
            141, payload=b'\x80', transport=1, base=dict(width=4, height=2)))
        self.assertEqual([f['frame_id'] for f in frames], [141])
        self.assertEqual(frames[0]['pixels'], bytes(7) + b'\xff')
        self.assertGreaterEqual(p.rejected, 2)

    def test_v3_target_geometry_checks_apply_to_packed_and_result_only(self):
        malformed = [dict(flags=15), dict(roi_x_min=0), dict(min_area=0),
                     dict(bbox_x_min=0), dict(target_sum_x=23),
                     dict(target_sum_y=14), dict(target_area=7),
                     dict(flags=7, **EMPTY_TARGET)]
        for transport in (5, 6):
            for changes in malformed:
                with self.subTest(transport=transport, changes=changes):
                    p = self.parser()
                    self.assertEqual([f['frame_id'] for f in p.feed(
                        output_packet(transport=transport, **changes) + packet(142))], [142])
                    self.assertGreaterEqual(p.rejected, 1)

    def test_v3_crc_covers_wire_payload_and_header_and_truncations_recover(self):
        packed = output_packet(payload=b'\x81\x03\x00')
        for offset in (6, 33, 70, 72, len(packed) - 1):
            with self.subTest(offset=offset):
                bad = bytearray(packed)
                bad[offset] ^= 1
                p = self.parser()
                frames = p.feed(bad + output_packet(143, transport=6) + packet(144))
                self.assertEqual([f['frame_id'] for f in frames], [143, 144])
                self.assertGreaterEqual(p.rejected, 1)
        for original in (packed, output_packet(transport=6)):
            for length in (35, 71, 72, len(original) - 1):
                with self.subTest(packet_length=len(original), truncated=length):
                    p = self.parser()
                    self.assertEqual(p.feed(original[:length]), [])
                    self.assertTrue(p.finish())
                    p = self.parser()
                    self.assertEqual([f['frame_id'] for f in p.feed(
                        original[:length] + output_packet(145, transport=6))], [145])

    def test_v3_saving_results_only_never_creates_image_and_preserves_orphans(self):
        frames = self.parser().feed(output_packet(150, transport=6)
                                    + output_packet(150, transport=6, flags=6, **EMPTY_TARGET))
        with tempfile.TemporaryDirectory() as d:
            out = pathlib.Path(d)
            orphan_image = out / 'frame_0000000150.pgm'
            orphan_meta = out / 'frame_0000000150_1.json'
            orphan_image.write_bytes(b'original image')
            orphan_meta.write_text('original metadata', encoding='utf-8')
            paths = [self.receiver.save_frame(frame, out) for frame in frames]
            self.assertEqual([path.name for path in paths],
                             ['frame_0000000150_2.json', 'frame_0000000150_3.json'])
            self.assertEqual(list(out.glob('*.pgm')), [orphan_image])
            self.assertEqual(orphan_image.read_bytes(), b'original image')
            self.assertEqual(orphan_meta.read_text(encoding='utf-8'), 'original metadata')
            for frame, path in zip(frames, paths):
                meta = json.loads(path.read_text(encoding='utf-8'))
                self.assertIsNone(meta['image_file'])
                self.assertEqual(meta['pixel_format'], 'none')
                self.assertEqual(meta['payload_length'], 0)
                self.assertNotIn('pixels', meta)
                self.assertEqual(meta['target'], frame['target'])
            with (out / 'metadata.csv').open(newline='', encoding='utf-8') as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual([row['target_valid'] for row in rows], ['True', 'False'])
            self.assertTrue(all(row['image_file'] == '' and row['pixel_format'] == 'none' for row in rows))

    def test_v3_mixed_save_expands_pgm_records_wire_size_and_schema_safely(self):
        frames = self.parser().feed(packet(151) + target_packet(152)
                                    + output_packet(153, b'\x01\x80\x00', 1)
                                    + output_packet(154, transport=6, flags=6, **EMPTY_TARGET))
        with tempfile.TemporaryDirectory() as d:
            out = pathlib.Path(d)
            old_csv = b'version,frame_id,centroid_x\r\n1,5,8\r\n'
            v2_csv = (','.join(self.receiver.CSV_FIELDS[:-1]) + '\n').encode()
            (out / 'metadata.csv').write_bytes(old_csv)
            (out / 'metadata_v2.csv').write_bytes(v2_csv)
            paths = [self.receiver.save_frame(frame, out) for frame in frames]
            self.assertEqual((out / 'metadata.csv').read_bytes(), old_csv)
            self.assertEqual((out / 'metadata_v2.csv').read_bytes(), v2_csv)
            with (out / 'metadata_v3.csv').open(newline='', encoding='utf-8') as handle:
                reader = csv.DictReader(handle)
                rows = list(reader)
                self.assertEqual(reader.fieldnames[-1], 'pixel_format')
                self.assertEqual(reader.fieldnames, list(self.receiver.CSV_FIELDS))
            self.assertEqual([row['pixel_format'] for row in rows], ['gray8', 'gray8', 'mono1', 'none'])
            self.assertEqual([row['payload_length'] for row in rows], ['8', '24', '3', '0'])
            self.assertEqual(rows[2]['target_valid'], '')
            self.assertEqual(len(list(out.glob('*.pgm'))), 3)
            self.assertEqual(paths[2].read_bytes(), b'P5\n6 4\n255\n' + frames[2]['pixels'])
            self.assertNotIn('target', json.loads(paths[2].with_suffix('.json').read_text(encoding='utf-8')))

    def test_v3_result_display_uses_fresh_blank_canvas_and_marks_results_only(self):
        class FakeCv:
            COLOR_GRAY2BGR = 1
            FONT_HERSHEY_SIMPLEX = 2

            def __init__(self):
                self.calls = []

            def cvtColor(self, original, conversion):
                self.calls.append(('copy', original, conversion))
                return object()

            def rectangle(self, *args):
                self.calls.append(('rectangle', *args))

            def circle(self, *args):
                self.calls.append(('circle', *args))

            def putText(self, *args):
                self.calls.append(('text', *args))

        class FakeArray:
            uint8 = object()

            def __init__(self):
                self.calls = []

            def zeros(self, dimensions, dtype):
                canvas = object()
                self.calls.append((dimensions, dtype, canvas))
                return canvas

            def frombuffer(self, *args, **kwargs):
                raise AssertionError('result-only packet must not interpret or reuse image data')

        frames = self.parser().feed(output_packet(155, transport=6)
                                    + output_packet(156, transport=6, flags=6, **EMPTY_TARGET))
        np = FakeArray()
        cv = FakeCv()
        displayed = [self.receiver.display_frame(frame, cv, np) for frame in frames]
        self.assertEqual([call[:2] for call in np.calls], [((4, 6), np.uint8)] * 2)
        self.assertIsNot(np.calls[0][2], np.calls[1][2])
        self.assertIsNot(displayed[0], displayed[1])
        texts = [call[2] for call in cv.calls if call[0] == 'text']
        self.assertEqual(texts, ['Features only - Target sensor=(4,2)', 'Features only - No target'])
        circles = [call for call in cv.calls if call[0] == 'circle']
        self.assertEqual(len(circles), 1)
        self.assertEqual(circles[0][2], (3, 1))
        self.assertTrue(any(call[0] == 'rectangle' and call[2:4] == ((2, 1), (4, 2)) for call in cv.calls))

    def test_v3_recorded_cli_counts_results_only_and_saves_no_pgm(self):
        script = pathlib.Path(__file__).with_name('receiver.py')
        wires = [output_packet(160, transport=6),
                 output_packet(161, transport=6, flags=6, **EMPTY_TARGET)]
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            recorded = root / 'wire.bin'
            recorded.write_bytes(b''.join(wires))
            result = subprocess.run(
                [sys.executable, str(script), '--input', str(recorded),
                 '--out', str(root / 'frames'), '--count', '2'],
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, '')
            self.assertIn('Received 2 valid frames;', result.stdout)
            self.assertIn('pixel_format=none', result.stdout)
            self.assertIn('target_valid=False', result.stdout)
            self.assertEqual(len(list((root / 'frames').glob('*.json'))), 2)
            self.assertEqual(len(list((root / 'frames').glob('*.pgm'))), 0)

    def test_v3_recorded_cli_replays_mixed_stream_and_stops_at_requested_count(self):
        script = pathlib.Path(__file__).with_name('receiver.py')
        wire = (packet(170) + output_packet(171, transport=6)
                + output_packet(172, b'\x81\x01', 1, dict(width=3, height=3))
                + target_packet(173) + output_packet(174, transport=6))
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            recorded = root / 'wire.bin'
            recorded.write_bytes(wire)
            result = subprocess.run(
                [sys.executable, str(script), '--input', str(recorded),
                 '--out', str(root / 'frames'), '--count', '4'],
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Received 4 valid frames;', result.stdout)
            self.assertEqual(len(list((root / 'frames').glob('*.json'))), 4)
            self.assertEqual(len(list((root / 'frames').glob('*.pgm'))), 3)
            image = root / 'frames' / 'frame_0000000172.pgm'
            self.assertEqual(image.read_bytes(), b'P5\n3 3\n255\n' + b'\xff' + bytes(6) + b'\xff\xff')


if __name__ == '__main__':
    unittest.main()
