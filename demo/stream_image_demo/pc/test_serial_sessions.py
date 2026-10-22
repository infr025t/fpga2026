"""Live connection recovery and raw recording, without real serial hardware."""
import contextlib
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

import receiver
import test_receiver as wire


class Clock:
    def __init__(self):
        self.now = 0.0
        self.sleeps = []

    def sleep(self, duration):
        self.sleeps.append(duration)
        self.now += duration


class Port:
    def __init__(self, *events, clock=None):
        self.events = iter(events)
        self.buffer = b''
        self.closed = False
        self.clock = clock

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.closed = True

    @property
    def in_waiting(self):
        return len(self.buffer)

    def read(self, count):
        if not self.buffer:
            try:
                event = next(self.events)
            except StopIteration:
                raise KeyboardInterrupt
            if isinstance(event, BaseException):
                raise event
            self.buffer = event
        data, self.buffer = self.buffer[:count], self.buffer[count:]
        return data


class SerialSessionTests(unittest.TestCase):
    def invoke(self, factory, args, cv=None, np=None, clock=None):
        clock = clock or Clock()
        serial = types.SimpleNamespace(Serial=factory, SerialException=OSError)
        modules = {'serial': serial}
        if cv is not None:
            modules.update(cv2=cv, numpy=np)
        stdout, stderr = io.StringIO(), io.StringIO()
        exit_code = 0
        with (mock.patch.dict(sys.modules, modules),
              mock.patch.object(sys, 'argv', ['receiver.py', '--port', 'mock', *args]),
              mock.patch.object(receiver.time, 'monotonic', side_effect=lambda: clock.now),
              mock.patch.object(receiver.time, 'sleep', side_effect=clock.sleep),
              contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr)):
            try:
                receiver.main()
            except SystemExit as exc:
                exit_code = exc.code
        return exit_code, stdout.getvalue(), stderr.getvalue(), clock

    def test_reconnect_recovers_complete_tail_resets_preview_and_records_separate_streams(self):
        old = wire.packet(2, bytes(100), width=10, height=10)[:38]
        first_bytes = (wire.target_packet(10, base=dict(mode=1))
                       + wire.output_packet(11, transport=6)
                       + old + wire.output_packet(12, transport=6))
        second_bytes = (wire.output_packet(13, transport=6)
                        + wire.output_packet(14) + wire.output_packet(15, transport=6))
        first, second = Port(first_bytes, OSError('USB disconnected')), Port(second_bytes)
        factory = mock.Mock(side_effect=[first, second])
        cv, np = wire.DisplayCv(), wire.DisplayNumpy()
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            # An unrelated old numbered recording must not be overwritten.
            (root / 'wire_001.bin').write_bytes(b'old evidence')
            args = ['--reconnect', '0.5', '--record-wire', str(root / 'wire.bin'),
                    '--out', str(root / 'frames'), '--count', '6',
                    '--display', '--hold-preview']
            code, output, error, clock = self.invoke(factory, args, cv, np)
            self.assertEqual(code, 0, error)
            self.assertEqual(factory.call_count, 2)
            self.assertTrue(first.closed and second.closed and cv.closed)
            self.assertEqual((root / 'wire.bin').read_bytes(), first_bytes)
            self.assertEqual((root / 'wire_001.bin').read_bytes(), b'old evidence')
            self.assertEqual((root / 'wire_002.bin').read_bytes(), second_bytes)
            metas = [json.loads(p.read_text()) for p in sorted((root / 'frames').glob('*.json'))]
            self.assertEqual([f['frame_id'] for f in metas], list(range(10, 16)))
            self.assertEqual(len(list((root / 'frames').glob('*.pgm'))), 2)
            self.assertTrue(all(f['image_file'] is None for f in metas if f['pixel_format'] == 'none'))
            self.assertIn('Received 6 valid frames;', output)
            self.assertIn('rejected/resynchronized 1 candidates', output)
            self.assertIn('reconnected', error)
            self.assertEqual(clock.sleeps, [0.25, 0.25])
            self.assertIn('Disconnected - retrying', cv.texts)
            # One disconnected canvas plus one blank features-only frame on the
            # new connection. It must not reuse preview frame 10 for target 13.
            self.assertEqual(np.blanks, [(4, 6), (4, 6)])
            self.assertIn('Preview frame=14 (held)', cv.texts)
            # Raw logs remain usable by the real file-input CLI independently.
            for name in ('wire.bin', 'wire_002.bin'):
                replay = subprocess.run(
                    [sys.executable, str(Path(receiver.__file__)), '--input', str(root / name),
                     '--out', str(root / (name + '.frames')), '--count', '3'],
                    capture_output=True, text=True, timeout=10)
                self.assertEqual(replay.returncode, 0, replay.stderr)

    def test_initial_open_failures_wait_before_retry_and_do_not_create_extra_segments(self):
        clock, calls = Clock(), []
        stream = Port(wire.output_packet(20, transport=6))
        results = iter([OSError('port missing'), OSError('still missing'), stream])
        def open_port(*args, **kwargs):
            calls.append(clock.now)
            value = next(results)
            if isinstance(value, BaseException):
                raise value
            return value
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            code, _, error, _ = self.invoke(mock.Mock(side_effect=open_port),
                ['--reconnect', '0.6', '--record-wire', str(root / 'capture.bin'),
                 '--out', str(root / 'frames'), '--count', '1'], clock=clock)
            self.assertEqual(code, 0, error)
            self.assertEqual(len(calls), 3)
            for actual, expected in zip(calls, (0, 0.6, 1.2)):
                self.assertAlmostEqual(actual, expected)
            self.assertTrue(all(0 < delay <= 0.25 for delay in clock.sleeps))
            self.assertEqual(list(root.glob('capture*.bin')), [root / 'capture.bin'])
            self.assertEqual((root / 'capture.bin').read_bytes(), wire.output_packet(20, transport=6))
            self.assertTrue(stream.closed)

    def test_lost_half_packet_cannot_cross_connection_even_with_idle_resync_disabled(self):
        original = wire.packet(40, bytes(100), width=10, height=10)
        first, second = Port(original[:35], OSError('removed')), Port(wire.packet(41))
        with tempfile.TemporaryDirectory() as d:
            code, _, error, _ = self.invoke(mock.Mock(side_effect=[first, second]),
                ['--reconnect', '0.1', '--idle-resync', '0', '--count', '1', '--out', d])
            self.assertEqual(code, 0, error)
            frames = [json.loads(p.read_text()) for p in Path(d).glob('*.json')]
            self.assertEqual([f['frame_id'] for f in frames], [41])
            self.assertTrue(first.closed and second.closed)

    def test_recording_preserves_first_byte_when_availability_query_disconnects(self):
        class RemovedPort(Port):
            @property
            def in_waiting(self):
                raise OSError('device removed after first byte')
        first, second = RemovedPort(b'FPG1'), Port(wire.packet(42))
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            code, _, error, _ = self.invoke(mock.Mock(side_effect=[first, second]),
                ['--reconnect', '0.1', '--record-wire', str(root / 'wire.bin'),
                 '--count', '1', '--out', str(root / 'frames')])
            self.assertEqual(code, 0, error)
            self.assertEqual((root / 'wire.bin').read_bytes(), b'F')
            self.assertEqual((root / 'wire_001.bin').read_bytes(), wire.packet(42))
            self.assertTrue(first.closed and second.closed)

    def test_without_reconnect_open_failure_is_an_actionable_nonzero_exit(self):
        factory = mock.Mock(side_effect=OSError('port is busy'))
        code, output, error, _ = self.invoke(factory, [])
        self.assertEqual(code, 1)
        self.assertIn('Received 0 valid frames', output)
        self.assertIn('Serial connection failed (mock): port is busy', error)
        self.assertNotIn('Traceback', error)
        self.assertEqual(factory.call_count, 1)

    def test_without_reconnect_read_failure_keeps_saved_frame_and_raw_bytes(self):
        data = wire.packet(47)
        stream = Port(data, OSError('USB removed'))
        factory = mock.Mock(return_value=stream)
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            code, output, error, _ = self.invoke(factory,
                ['--record-wire', str(root / 'wire.bin'), '--out', str(root / 'frames')])
            self.assertEqual(code, 1)
            self.assertIn('Received 1 valid frames', output)
            self.assertIn('USB removed', error)
            self.assertNotIn('Traceback', error)
            self.assertEqual((root / 'wire.bin').read_bytes(), data)
            self.assertEqual(len(list((root / 'frames').glob('*.json'))), 1)
            self.assertEqual(factory.call_count, 1)
            self.assertTrue(stream.closed)

    def test_repeated_reconnections_close_ports_and_preserve_duplicate_frame_ids(self):
        data = wire.packet(7)
        ports = [Port(data, OSError('removed')) for _ in range(32)]
        factory = mock.Mock(side_effect=ports)
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            code, output, error, _ = self.invoke(factory,
                ['--reconnect', '0.001', '--record-wire', str(root / 'wire.bin'),
                 '--out', str(root / 'frames'), '--count', '32'])
            self.assertEqual(code, 0, error)
            self.assertIn('Received 32 valid frames', output)
            self.assertEqual(factory.call_count, 32)
            self.assertTrue(all(port.closed for port in ports))
            recordings = list(root.glob('wire*.bin'))
            self.assertEqual(len(recordings), 32)
            self.assertTrue(all(path.read_bytes() == data for path in recordings))
            self.assertEqual(len(list((root / 'frames').glob('*.pgm'))), 32)
            with (root / 'frames/metadata.csv').open(newline='', encoding='utf-8') as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 32)
            self.assertTrue(all(row['frame_id'] == '7' for row in rows))
            self.assertEqual(len({row['image_file'] for row in rows}), 32)

    def test_display_quit_is_handled_during_reconnect_backoff(self):
        factory = mock.Mock(side_effect=OSError('missing'))
        cv, np = wire.DisplayCv(), wire.DisplayNumpy()
        cv.waitKey = mock.Mock(side_effect=[-1, ord('q')])
        code, _, error, clock = self.invoke(factory, ['--reconnect', '2', '--display'], cv, np)
        self.assertEqual(code, 0, error)
        self.assertEqual(factory.call_count, 1)
        self.assertEqual(clock.sleeps, [0.25])
        self.assertTrue(cv.closed)
        self.assertIn('Disconnected - retrying', cv.texts)

    def test_keyboard_interrupt_closes_and_flushes_raw_recording(self):
        stream = Port(b'noiseFPG1partial', KeyboardInterrupt())
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'nested' / 'wire.bin'
            code, _, error, _ = self.invoke(mock.Mock(return_value=stream), ['--record-wire', str(path)])
            self.assertEqual(code, 0, error)
            self.assertTrue(stream.closed)
            self.assertEqual(path.read_bytes(), b'noiseFPG1partial')

    def test_existing_recording_fails_before_opening_port_and_is_preserved(self):
        factory = mock.Mock()
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'wire.bin'
            path.write_bytes(b'historical bytes')
            code, _, error, _ = self.invoke(factory, ['--record-wire', str(path)])
            self.assertEqual(code, 2)
            self.assertIn('recording file already exists', error)
            factory.assert_not_called()
            self.assertEqual(path.read_bytes(), b'historical bytes')

    def test_recording_write_failure_stops_instead_of_reconnecting(self):
        stream = Port(wire.packet(43))
        factory = mock.Mock(return_value=stream)
        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(receiver.WireRecorder, 'write',
                                   side_effect=receiver.RecordingError('disk full')):
                code, _, error, clock = self.invoke(factory,
                    ['--reconnect', '1', '--record-wire', str(Path(d) / 'wire.bin')])
            self.assertEqual(code, 1)
            self.assertIn('disk full', error)
            self.assertNotIn('retrying', error)
            self.assertEqual(factory.call_count, 1)
            self.assertEqual(clock.sleeps, [])
            self.assertTrue(stream.closed)
        # Real OSError from the file handle must be classified the same way.
        recorder = receiver.WireRecorder('unused')
        recorder.handle = mock.Mock()
        recorder.handle.write.side_effect = OSError('disk full')
        with self.assertRaises(receiver.RecordingError):
            recorder.write(b'x')

    def test_recording_rotation_failure_closes_new_port_without_retrying(self):
        first, second = Port(wire.packet(44), OSError('removed')), Port(wire.packet(45))
        factory = mock.Mock(side_effect=[first, second])
        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(receiver.WireRecorder, 'rotate', side_effect=PermissionError('cannot rotate')):
                code, output, error, _ = self.invoke(factory,
                    ['--reconnect', '0.1', '--record-wire', str(Path(d) / 'wire.bin'), '--out', str(Path(d) / 'frames')])
            self.assertEqual(code, 1)
            self.assertIn('Received 1 valid frames', output)
            self.assertIn('cannot rotate', error)
            self.assertEqual(factory.call_count, 2)
            self.assertTrue(first.closed and second.closed)

    def test_frame_save_error_is_not_treated_as_serial_disconnection(self):
        stream = Port(wire.packet(46))
        factory = mock.Mock(return_value=stream)
        with mock.patch.object(receiver, 'save_frame', side_effect=OSError('output full')):
            code, _, error, clock = self.invoke(factory, ['--reconnect', '1'])
        self.assertEqual(code, 1)
        self.assertIn('output full', error)
        self.assertNotIn('retrying', error)
        self.assertEqual(factory.call_count, 1)
        self.assertEqual(clock.sleeps, [])
        self.assertTrue(stream.closed)

    def test_invalid_reconnect_values_and_file_input_options_fail_before_optional_imports(self):
        script = str(Path(receiver.__file__))
        for value in ('-1', 'nan', 'inf'):
            with self.subTest(value=value):
                result = subprocess.run([sys.executable, script, '--port', 'unused', '--reconnect', value],
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertIn('--reconnect must be a finite nonnegative number', result.stderr)
                self.assertNotIn('Traceback', result.stderr)
        for options in (['--reconnect', '1'], ['--record-wire', 'unused.bin']):
            result = subprocess.run([sys.executable, script, '--input', 'missing.bin', *options],
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertIn('require --port', result.stderr)


if __name__ == '__main__':
    unittest.main()
