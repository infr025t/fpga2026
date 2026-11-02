"""自主识别只读观察器：先收包落盘，关串口后才做整数参考验证。

运行：python pc/observe_auto.py --frames 20 --out reports/auto_observation
回放：python pc/observe_auto.py --wire reports/auto_observation/wire.bin --out reports/replay
本程序仅允许 COM10，不发送串口字节，不访问 JTAG，也不改变开发板模式。
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

from auto_protocol import StreamParser
from auto_capture import capture_stream
# 显式重导出旧入口的公共对象，保留现有调用方和测试的导入方式。
from auto_collect import FrameCollector, json_default, json_object, save_json
from auto_verify import CLASSES, verify_frame

ROOT = Path(__file__).resolve().parents[1]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wire', type=Path, help='回放已保存字节，完全不打开串口')
    parser.add_argument('--port', default='COM10', choices=['COM10'], help='唯一允许的只读观察端口')
    parser.add_argument('--baud', type=int, default=12_000_000, choices=[12_000_000])
    parser.add_argument('--frames', type=int, default=20, help='需完整核验通过的帧数')
    parser.add_argument('--timeout', type=float, default=30, help='接收最长秒数')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--truth', help='只在预测完成后评分；不参与参考算法')
    args = parser.parse_args(argv)
    if args.frames < 1 or args.timeout <= 0:
        parser.error('frames and timeout must be positive')
    args.out.mkdir(parents=True, exist_ok=True)
    if (args.out / 'wire.bin').exists() or (args.out / 'summary.json').exists():
        parser.error('output already contains observation evidence; use a new directory')
    if args.wire and args.wire.resolve() == (args.out / 'wire.bin').resolve():
        parser.error('wire source cannot be the output file')
    stream_parser = StreamParser()
    collector = FrameCollector(args.out)
    started = time.monotonic()
    capture = capture_stream(wire_path=args.wire, out=args.out, port=args.port,
                             baud=args.baud, frames=args.frames, timeout=args.timeout,
                             stream_parser=stream_parser, collector=collector,
                             started=started)
    capture_error = capture['capture_error']
    bytes_received = capture['bytes_received']
    timed_out = capture['timed_out']
    capture_seconds = capture['capture_seconds']
    # 至此串口已关闭；参考计算不会堵塞接收线程或对开发板形成反压。
    import integer_cnn
    from norm_ref import MODEL_SHA
    model_path = ROOT / 'model' / 'model.bin'
    model_sha = hashlib.sha256(model_path.read_bytes()).hexdigest()
    model_error = None if model_sha == MODEL_SHA else 'frozen_model_sha256_mismatch'
    model = integer_cnn.load(model_path.parent)
    rows = []
    for folder in collector.paths:
        try:
            row = verify_frame(folder, model)
        except (ValueError, KeyError, IndexError, TypeError) as exc:
            row = dict(passed=False, errors=['reference_exception: ' + repr(exc)], characters=[])
        if model_error:
            row['passed'] = False
            row['errors'].append(model_error)
        if args.truth is not None:
            row['truth_for_scoring_only'] = args.truth
            row['truth_exact'] = row.get('hardware_prediction') == args.truth
        save_json(folder / 'result.json', row)
        rows.append(row)
        print(json.dumps({key:row[key] for key in ('frame_id', 'passed', 'hardware_prediction', 'errors') if key in row}), flush=True)
    verified = sum(row['passed'] for row in rows)
    summary = dict(passed=verified >= args.frames and not capture_error and not model_error,
                   requested_frames=args.frames, captured_complete_frames=len(rows), verified_frames=verified,
                   mismatched_frames=sum(not row['passed'] for row in rows),
                   verified_characters=sum(len(row['characters']) for row in rows if row['passed']),
                   groups=collector.stats, parser=dict(stream_parser.stats), bytes_received=bytes_received,
                   timed_out=timed_out, capture_error=capture_error, capture_seconds=capture_seconds,
                   total_seconds=time.monotonic() - started, model_sha256=model_sha, model_error=model_error,
                   source=str(args.wire) if args.wire else f'{args.port}@{args.baud}',
                   read_only=True, scope='Complete groups only; exact integer reference with versioned dynamic ROI, prefix exclusion and ASG4/5 touching split; not arbitrary-plate recognition accuracy',
                   frames=[str(folder.relative_to(args.out) / 'result.json') for folder in collector.paths])
    if args.truth is not None:
        summary.update(truth_for_scoring_only=args.truth, truth_exact_frames=sum(row.get('truth_exact', False) for row in rows))
    save_json(args.out / 'summary.json', summary)
    print(json.dumps(summary), flush=True)
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
