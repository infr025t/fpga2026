"""只读串口或文件采集；退出前关闭源并记录未完成分组。"""
import time


def capture_stream(*, wire_path, out, port, baud, frames, timeout,
                   stream_parser, collector, started):
    """保留整块原始字节，完整帧达到上限后结束接纳，不执行参考计算。"""
    # 参数由命令入口校验；生产入口仅允许COM10、12000000波特率。
    capture_error = None
    bytes_received = 0
    timed_out = False
    try:
        if wire_path:
            source = wire_path.open('rb')
        else:
            import serial
            # 禁用流控；端口实例上只有 read，不调用 write/reset/write_control。
            source = serial.Serial(port, baud, timeout=0.05,
                                   xonxoff=False, rtscts=False, dsrdtr=False)
        with source, (out / 'wire.bin').open('wb') as wire:
            while collector.stats['complete_groups'] < frames:
                if time.monotonic() - started >= timeout:
                    timed_out = True
                    break
                data = source.read(4096)
                if not data:
                    if wire_path:
                        break
                    continue
                wire.write(data)
                bytes_received += len(data)
                for packet in stream_parser.feed(data):
                    # 当前块仍完整保存，但最多接纳所请求数量的完整帧。
                    if collector.stats['complete_groups'] < frames:
                        collector.feed(packet)
    except (OSError, ValueError, KeyboardInterrupt) as exc:
        capture_error = type(exc).__name__ + ': ' + str(exc)
    finally:
        tail = stream_parser.finish()
        if tail:
            for packet in tail:
                if collector.stats['complete_groups'] < frames:
                    collector.feed(packet)
        collector.finish()
    capture_seconds = time.monotonic() - started
    return dict(capture_error=capture_error, bytes_received=bytes_received,
                timed_out=timed_out, capture_seconds=capture_seconds)
