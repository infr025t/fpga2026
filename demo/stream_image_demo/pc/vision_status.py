"""Optional VST1 diagnostics for vision_top; image processing never waits for PC."""
import argparse
import binascii
import json
import math
from pathlib import Path
import struct

from receiver import SerialInput

MAGIC = b'VST1'
PACKET = struct.Struct('<4sBBH12IH')
FIELDS = ('frame_id', 'processed_frames', 'displayed_frames', 'display_dropped',
          'display_skipped', 'capture_errors', 'line_errors', 'input_overflows',
          'processing_errors', 'display_errors', 'processing_fps', 'last_latency_cycles')


class StatusParser:
    def __init__(self):
        self.buffer = bytearray()
        self.rejected = 0

    def feed(self, chunk):
        self.buffer.extend(chunk)
        statuses = []
        while True:
            pos = self.buffer.find(MAGIC)
            if pos < 0:
                self.buffer[:] = self.buffer[-3:]
                break
            if pos:
                del self.buffer[:pos]
            if len(self.buffer) < 8:
                break
            version, flags, length = struct.unpack_from('<BBH', self.buffer, 4)
            if version != 1 or flags & ~15 or length != PACKET.size:
                self.rejected += 1
                del self.buffer[0]
                continue
            if len(self.buffer) < PACKET.size:
                break
            values = PACKET.unpack_from(self.buffer)
            if binascii.crc_hqx(self.buffer[4:PACKET.size-2], 0xffff) != values[-1]:
                self.rejected += 1
                del self.buffer[0]
                continue
            status = dict(zip(FIELDS, values[4:-1]))
            status.update(version=version, configured=bool(flags & 1),
                          camera_fault=bool(flags & 2), paused=bool(flags & 4),
                          pattern=bool(flags & 8))
            statuses.append(status)
            del self.buffer[:PACKET.size]
        return statuses

    def finish(self):
        truncated = self.buffer.startswith(MAGIC)
        self.buffer.clear()
        return truncated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--input', type=Path)
    source.add_argument('--port')
    parser.add_argument('--baud', type=int, default=1000000)
    parser.add_argument('--count', type=int)
    parser.add_argument('--out', type=Path, default=Path('status_logs'))
    parser.add_argument('--reconnect', type=float, default=0)
    args = parser.parse_args()
    if args.baud < 1 or (args.count is not None and args.count < 1):
        parser.error('--baud and --count must be positive')
    if not math.isfinite(args.reconnect) or args.reconnect < 0:
        parser.error('--reconnect must be finite and nonnegative')
    if args.input and args.reconnect:
        parser.error('--reconnect requires --port')
    decoder = StatusParser()
    count, index = 0, 0
    try:
        if args.input:
            stream = args.input.open('rb')
        else:
            import serial
            stream = SerialInput(serial, args.port, args.baud, args.reconnect)
        with stream:
            args.out.mkdir(parents=True, exist_ok=True)
            while args.count is None or count < args.count:
                chunk = stream.read(4096) if args.input else stream.read()
                if chunk is None:
                    decoder.finish()
                    continue
                if not chunk and args.input:
                    if decoder.finish():
                        parser.exit(1, 'Input ended with an incomplete status packet.\n')
                    break
                for status in decoder.feed(chunk):
                    while True:
                        index += 1
                        path = args.out / f'status_{index:010d}.json'
                        try:
                            handle = path.open('x', encoding='utf-8')
                            break
                        except FileExistsError:
                            continue
                    with handle:
                        handle.write(json.dumps(status, indent=2) + '\n')
                    count += 1
                    print(f'{path}: processed={status["processed_frames"]} '
                          f'fps={status["processing_fps"]} dropped={status["display_dropped"]}')
                    if args.count is not None and count >= args.count:
                        break
    except KeyboardInterrupt:
        return
    except OSError as exc:
        parser.exit(1, f'Status I/O error: {exc}\n')
    print(f'Received {count} valid status packets; rejected {decoder.rejected}.')
    if args.count is not None and count < args.count:
        parser.exit(1, 'Input ended before requested status count.\n')


if __name__ == '__main__':
    main()
