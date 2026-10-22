"""FPG1 UART receiver. Pure stdlib parsing/PGM output; pyserial for a real port.

CRC-16/CCITT-FALSE: polynomial 0x1021, init 0xffff, no reflection/xorout.
CRC covers header[4:] and the wire payload and is sent little endian. Version 1
has a 32-byte header; versions 2/3 have a 72-byte header. Version 3 transports
packed binary Sobel pixels or only ROI target statistics. Coordinates
refer to the sensor (the cropped image origin is sensor (1,1)). The legacy
bright-pixel centroid remains separate from the version 2 target centroid.
"""
import argparse
import binascii
import csv
import json
import math
from pathlib import Path
import struct
import time

MAGIC = b'FPG1'
HEADER = struct.Struct('<4sBBHHHIIIII')
TARGET_EXTENSION = struct.Struct('<BBHHHHHHHHIIIIIH')
KEYS = ('version', 'mode', 'width', 'height', 'threshold', 'frame_id',
        'payload_length', 'bright_count', 'sum_x', 'sum_y')
MAX_PIXELS = 320 * 240
BOX_KEYS = ('x_min', 'y_min', 'x_max', 'y_max')
TARGET_CSV_KEYS = ('config_valid', 'valid', 'dark', 'threshold',
                   'roi_x_min', 'roi_y_min', 'roi_x_max', 'roi_y_max',
                   'area', 'sum_x', 'sum_y', 'min_area', 'max_area',
                   'bbox_x_min', 'bbox_y_min', 'bbox_x_max', 'bbox_y_max',
                   'centroid_x', 'centroid_y')
CSV_FIELDS = (*KEYS, 'centroid_x', 'centroid_y', 'image_file',
              *('target_' + key for key in TARGET_CSV_KEYS), 'pixel_format')
MONO1_BYTES = tuple(bytes(255 if value & (1 << bit) else 0 for bit in range(8))
                    for value in range(256))


def _sum_bounds(area, low, high, capacity):
    """Possible axis sums for distinct pixels inside a rectangular box."""
    whole, remainder = divmod(area, capacity)
    minimum = area * low + capacity * whole * (whole - 1) // 2 + whole * remainder
    maximum = area * (low + high) - minimum
    # Both bounding-box endpoints must actually occur in the selected pixels.
    if low != high:
        minimum = max(minimum, (area - 1) * low + high)
        maximum = min(maximum, (area - 1) * high + low)
    return minimum, maximum


def _target_fields(values, width, height):
    (flags, threshold, rx0, ry0, rx1, ry1, bx0, by0, bx1, by1,
     area, sx, sy, minimum, maximum, reserved) = values
    if flags & ~0x07 or reserved:
        return False
    valid, dark, config_valid = bool(flags & 1), bool(flags & 2), bool(flags & 4)
    expected_config = (1 <= rx0 <= rx1 <= width and 1 <= ry0 <= ry1 <= height
                       and 1 <= minimum <= maximum <= width * height)
    if config_valid != expected_config:
        return False
    if valid != (config_valid and area > 0 and minimum <= area <= maximum):
        return False
    if not config_valid or not area:
        if any((area, sx, sy, bx0, by0, bx1, by1)):
            return False
    else:
        if not (rx0 <= bx0 <= bx1 <= rx1 and ry0 <= by0 <= by1 <= ry1):
            return False
        if area > (bx1 - bx0 + 1) * (by1 - by0 + 1):
            return False
        if area == 1 and (bx0 != bx1 or by0 != by1):
            return False
        sx_min, sx_max = _sum_bounds(area, bx0, bx1, by1 - by0 + 1)
        sy_min, sy_max = _sum_bounds(area, by0, by1, bx1 - bx0 + 1)
        if not (sx_min <= sx <= sx_max and sy_min <= sy <= sy_max):
            return False
    return dict(config_valid=config_valid, valid=valid, dark=dark,
                threshold=threshold, roi=dict(zip(BOX_KEYS, (rx0, ry0, rx1, ry1))),
                area=area, sum_x=sx, sum_y=sy, min_area=minimum, max_area=maximum,
                bbox=dict(zip(BOX_KEYS, (bx0, by0, bx1, by1))) if valid else None,
                centroid_x=sx // area if valid else None,
                centroid_y=sy // area if valid else None)


class FrameParser:
    """Incremental bounded parser; feed returns a list of validated frame dicts.

    Normal feeds always wait for the leading packet's declared length, so image
    pixels containing a valid packet cannot change parsing across read chunks.
    Only an explicit stream boundary may recover a later CRC-verified packet
    from an incomplete transfer. Call finish afterward to discard its tail.
    """
    def __init__(self):
        self.buffer = bytearray()
        self.rejected = 0

    def _candidate(self, pos):
        if len(self.buffer) - pos < HEADER.size:
            return None, None
        values = HEADER.unpack_from(self.buffer, pos)
        f = dict(zip(KEYS, values[1:]))
        w, h, n = f['width'], f['height'], f['payload_length']
        pixel_count = w * h
        if (values[0] != MAGIC or f['version'] not in (1, 2, 3) or f['mode'] not in (0, 1)
                or not (1 <= w <= 318 and 1 <= h <= 238)
                or n > MAX_PIXELS or f['threshold'] > 2047
                or f['bright_count'] > pixel_count
                or f['sum_x'] > f['bright_count'] * 319
                or f['sum_y'] > f['bright_count'] * 239):
            return False, None
        if f['version'] != 3 and n != pixel_count:
            return False, None
        header_size = HEADER.size
        pixel_format = 'gray8'
        if f['version'] in (2, 3):
            header_size += TARGET_EXTENSION.size
            if len(self.buffer) - pos < header_size:
                return None, None
            extension = TARGET_EXTENSION.unpack_from(self.buffer, pos + HEADER.size)
            has_target = True
            if f['version'] == 3:
                transport = self.buffer[pos + 70]
                if transport not in (1, 5, 6) or self.buffer[pos + 71]:
                    return False, None
                pixel_format = 'none' if transport == 6 else 'mono1'
                if pixel_format == 'mono1':
                    if f['mode'] != 1 or n != (pixel_count + 7) // 8:
                        return False, None
                elif n != 0:
                    return False, None
                has_target = transport != 1
                if not has_target and any(self.buffer[pos + 32:pos + 70]):
                    return False, None
                # The v2 reserved word is transport_flags plus reserved in v3.
                extension = (*extension[:-1], 0)
            if has_target:
                target = _target_fields(extension, w, h)
                if target is False:
                    return False, None
                f['target'] = target
        end = pos + header_size + n + 2
        if len(self.buffer) < end:
            return None, None
        expected, = struct.unpack_from('<H', self.buffer, end - 2)
        actual = binascii.crc_hqx(self.buffer[pos + 4:end - 2], 0xffff)
        if actual != expected:
            return False, None
        payload = bytes(self.buffer[pos + header_size:end - 2])
        if pixel_format == 'mono1':
            remaining = pixel_count % 8
            if remaining and payload[-1] & (0xff << remaining):
                return False, None
            payload = b''.join(MONO1_BYTES[value] for value in payload)[:pixel_count]
        f['pixels'] = payload
        f['pixel_format'] = pixel_format
        count = f['bright_count']
        f['centroid_x'] = f['sum_x'] // count if count else None
        f['centroid_y'] = f['sum_y'] // count if count else None
        return f, end

    def feed(self, chunk, *, boundary=False):
        self.buffer.extend(chunk)
        result = []
        while True:
            pos = self.buffer.find(MAGIC)
            if pos < 0:
                # Preserve possible fragmented magic, never unbounded noise.
                self.buffer[:] = self.buffer[-3:]
                break
            if pos:
                del self.buffer[:pos]
            frame, end = self._candidate(0)
            if frame is False:
                self.rejected += 1
                del self.buffer[0]
                continue
            if frame is None:
                if not boundary:
                    break
                # EOF or a caller-confirmed idle gap ends the old transfer.
                # Mere read fragmentation must never trigger this recovery.
                later = self.buffer.find(MAGIC, 4)
                recovered = False
                while later >= 0:
                    candidate, _ = self._candidate(later)
                    if candidate:
                        del self.buffer[:later]
                        self.rejected += 1
                        recovered = True
                        break
                    later = self.buffer.find(MAGIC, later + 1)
                if recovered:
                    continue
                break
            result.append(frame)
            del self.buffer[:end]
        return result

    def finish(self):
        """Discard ended-transfer leftovers; report full-magic truncation.

        A shorter magic suffix may simply be noise and is not enough evidence
        to classify a transfer as truncated. Call after a real stream EOF or
        an explicit idle boundary ends the transfer, not a single read timeout.
        """
        incomplete = self.buffer.startswith(MAGIC)
        if incomplete:
            self.rejected += 1
        self.buffer.clear()
        return incomplete


def display_geometry(frame):
    """Return ROI/target overlay positions in cropped-image coordinates."""
    target = frame.get('target')
    if target is None:
        return None

    def corners(box):
        return ((box['x_min'] - 1, box['y_min'] - 1),
                (box['x_max'] - 1, box['y_max'] - 1))

    return dict(roi=corners(target['roi']) if target['config_valid'] else None,
                bbox=corners(target['bbox']) if target['valid'] else None,
                centroid=(target['centroid_x'] - 1, target['centroid_y'] - 1)
                if target['valid'] else None,
                status=('Target' if target['valid'] else 'No target')
                if target['config_valid'] else 'Invalid target configuration')


def draw_target_overlay(picture, frame, cv2):
    """Draw only on a display copy; raw PGM and frame pixels stay unchanged."""
    geometry = display_geometry(frame)
    if geometry is None:
        return picture
    display = cv2.cvtColor(picture, cv2.COLOR_GRAY2BGR)
    if geometry['roi']:
        cv2.rectangle(display, *geometry['roi'], (0, 200, 255), 1)
    if geometry['bbox']:
        cv2.rectangle(display, *geometry['bbox'], (0, 255, 0), 1)
        cv2.circle(display, geometry['centroid'], 3, (0, 0, 255), -1)
    label = geometry['status']
    if frame.get('pixel_format') == 'none':
        label = 'Features only - ' + label
    if geometry['centroid']:
        target = frame['target']
        label += f" sensor=({target['centroid_x']},{target['centroid_y']})"
    cv2.putText(display, label, (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.4,
                (0, 255, 0) if geometry['bbox'] else (0, 0, 255), 1)
    return display


def display_frame(frame, cv2, np):
    """Create the current frame's canvas; result-only packets never reuse pixels."""
    if frame.get('pixel_format') == 'none':
        picture = np.zeros((frame['height'], frame['width']), dtype=np.uint8)
    else:
        picture = np.frombuffer(frame['pixels'], dtype=np.uint8).reshape(
            frame['height'], frame['width'])
    return draw_target_overlay(picture, frame, cv2)


class PreviewCache:
    """Optional display-only background; metadata and saved pixels stay current.

    A reset, repeated ID, or incompatible image settings invalidates the held
    image. The wire format has no source/session ID, so an undetectable camera
    change cannot be inferred here; the sender must supply a fresh preview.
    """
    def __init__(self):
        self.pixels = None
        self.preview_id = None
        self.last_id = None
        self.settings = None

    def render(self, frame, cv2, np):
        settings = (frame['width'], frame['height'], frame['mode'], frame['threshold'])
        if (settings != self.settings or
                (self.last_id is not None and frame['frame_id'] <= self.last_id)):
            self.pixels = None
            self.preview_id = None
        self.settings = settings
        self.last_id = frame['frame_id']
        if frame.get('pixel_format') != 'none':
            # Keep immutable, undecorated pixels, never an OpenCV display array.
            self.pixels = bytes(frame['pixels'])
            self.preview_id = frame['frame_id']
            return display_frame(frame, cv2, np)
        if self.pixels is None:
            return display_frame(frame, cv2, np)
        picture = np.frombuffer(self.pixels, dtype=np.uint8).reshape(
            frame['height'], frame['width'])
        display = draw_target_overlay(picture, frame, cv2)
        # Separate lines remain readable at the normal 318-pixel image width.
        for y, label in ((34, f'Preview frame={self.preview_id} (held)'),
                         (50, f'Target frame={frame["frame_id"]}')):
            cv2.putText(display, label, (4, y), cv2.FONT_HERSHEY_SIMPLEX,
                        0.4, (0, 200, 255), 1)
        return display


def read_serial_chunk(stream):
    """Wait for one byte, then drain only bytes already available (at most 4096).

    Reading 4096 directly with a timeout batches short features-only packets
    until the timeout expires, even though each packet is already complete.
    """
    first = stream.read(1)
    if not first:
        return first
    available = min(stream.in_waiting, 4095)
    return first + stream.read(available) if available else first


def _csv_path(out):
    """Keep old or foreign CSV schemas intact instead of appending shifted rows."""
    suffix = 0
    while True:
        name = 'metadata.csv' if suffix == 0 else (
            'metadata_v3.csv' if suffix == 1 else f'metadata_v3_{suffix - 1}.csv')
        path = out / name
        if not path.exists() or path.stat().st_size == 0:
            return path
        try:
            with path.open(newline='', encoding='utf-8-sig') as handle:
                if next(csv.reader(handle), None) == list(CSV_FIELDS):
                    return path
        except (UnicodeError, csv.Error):
            # A foreign or damaged schema is not safe to append to.
            pass
        suffix += 1


def _csv_row(meta):
    row = {key: value for key, value in meta.items() if key != 'target'}
    target = meta.get('target')
    if target is not None:
        for key in TARGET_CSV_KEYS:
            if key.startswith('roi_'):
                value = target['roi'][key[4:]]
            elif key.startswith('bbox_'):
                value = target['bbox'][key[5:]] if target['bbox'] else None
            else:
                value = target[key]
            row['target_' + key] = value
    return row


def save_frame(frame, out):
    """Write metadata and, when present, a lossless expanded-pixel PGM.

    Return the image path, or the JSON path for a result-only packet.
    """
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    base = f"frame_{frame['frame_id']:010d}"
    image_present = frame.get('pixel_format', 'gray8') != 'none'
    # Preserve frames if the FPGA resets and its frame counter starts again.
    # Either artifact may remain after an interrupted save or a manual move.
    suffix = 0
    while True:
        stem = base if suffix == 0 else f"{base}_{suffix}"
        path = out / (stem + '.pgm')
        meta_path = out / (stem + '.json')
        if path.exists() or meta_path.exists():
            suffix += 1
            continue
        try:
            handle = path.open('xb') if image_present else meta_path.open('x', encoding='utf-8')
        except FileExistsError:
            suffix += 1
            continue
        break
    meta = {k: v for k, v in frame.items() if k != 'pixels'}
    meta.setdefault('pixel_format', 'gray8')
    meta['image_file'] = path.name if image_present else None
    if image_present:
        with handle:
            handle.write(f"P5\n{frame['width']} {frame['height']}\n255\n".encode('ascii') + frame['pixels'])
        with meta_path.open('x', encoding='utf-8') as handle:
            handle.write(json.dumps(meta, indent=2) + '\n')
    else:
        with handle:
            handle.write(json.dumps(meta, indent=2) + '\n')
    csv_path = _csv_path(out)
    has_header = csv_path.exists() and csv_path.stat().st_size > 0
    with csv_path.open('a', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS)
        if not has_header:
            writer.writeheader()
        writer.writerow(_csv_row(meta))
    return path if image_present else meta_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--port', help='e.g. COM5')
    source.add_argument('--input', type=Path, help='recorded binary wire stream')
    parser.add_argument('--baud', type=int, default=1000000)
    parser.add_argument('--out', type=Path, default=Path('frames'))
    parser.add_argument('--count', type=int, help='stop after this many valid frames')
    parser.add_argument('--display', action='store_true', help='requires optional opencv-python')
    parser.add_argument('--hold-preview', action='store_true',
                        help='with --display, draw new target results on the last compatible '
                             'image and label both frame IDs; saved files stay unchanged')
    parser.add_argument('--idle-resync', type=float, default=1.0, metavar='SECONDS',
                        help='recover truncated serial frames after this long without bytes '
                             '(default: 1; 0 disables); later old bytes are discarded')
    args = parser.parse_args()
    if args.count is not None and args.count < 1:
        parser.error('--count must be positive')
    if args.baud < 1:
        parser.error('--baud must be positive')
    if not math.isfinite(args.idle_resync) or args.idle_resync < 0:
        parser.error('--idle-resync must be a finite nonnegative number')
    if args.hold_preview and not args.display:
        parser.error('--hold-preview requires --display')
    if args.display:
        import cv2
        import numpy as np
    if args.input:
        stream = args.input.open('rb')
    else:
        import serial
        stream = serial.Serial(args.port, args.baud, timeout=0.25)
    decoder = FrameParser()
    preview = PreviewCache() if args.hold_preview else None
    count = 0
    incomplete_input = False
    try:
        with stream:
            last_data_at = None
            while args.count is None or count < args.count:
                chunk = stream.read(4096) if args.input else read_serial_chunk(stream)
                end_of_input = not chunk and args.input is not None
                if chunk:
                    last_data_at = time.monotonic()
                    frames = decoder.feed(chunk)
                elif end_of_input:
                    frames = decoder.feed(b'', boundary=True)
                else:
                    frames = []
                    if (args.idle_resync and last_data_at is not None
                            and time.monotonic() - last_data_at >= args.idle_resync):
                        frames = decoder.feed(b'', boundary=True)
                        decoder.finish()
                        last_data_at = None
                for frame in frames:
                    path = save_frame(frame, args.out)
                    count += 1
                    message = (f"{path}: mode={frame['mode']} pixel_format={frame['pixel_format']} "
                               f"bright_centroid=({frame['centroid_x']}, {frame['centroid_y']})")
                    if 'target' in frame:
                        target = frame['target']
                        message += (f" target_valid={target['valid']} area={target['area']} "
                                    f"target_centroid=({target['centroid_x']}, {target['centroid_y']})")
                    print(message)
                    if args.display:
                        picture = (preview.render(frame, cv2, np) if preview is not None
                                   else display_frame(frame, cv2, np))
                        cv2.imshow('FPGA camera', picture)
                        if cv2.waitKey(1) & 0xff == ord('q'):
                            return
                    if args.count is not None and count >= args.count:
                        break
                if args.display and not frames:
                    if cv2.waitKey(1) & 0xff == ord('q'):
                        return
                if end_of_input:
                    if args.count is None or count < args.count:
                        incomplete_input = decoder.finish()
                    break
    except KeyboardInterrupt:
        pass
    finally:
        if args.display:
            cv2.destroyAllWindows()
    print(f"Received {count} valid frames; rejected/resynchronized {decoder.rejected} candidates.")
    if args.input and args.count is not None and count < args.count:
        parser.exit(1, 'Input ended before requested frame count.\n')
    if incomplete_input:
        parser.exit(1, 'Input ended with an incomplete frame.\n')


if __name__ == '__main__':
    main()
