"""自主协议帧分组与证据落盘；本层不执行参考算法。"""
from collections import OrderedDict
import json
from pathlib import Path


def json_default(value):
    if isinstance(value, bytes):
        return {'__bytes_hex__': value.hex()}
    raise TypeError(type(value).__name__)


def json_object(value):
    if set(value) == {'__bytes_hex__'}:
        return bytes.fromhex(value['__bytes_hex__'])
    return value


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=json_default), encoding='utf-8')


class FrameCollector:
    """只保留最多八组待完成帧；已完成帧立即写盘，不执行图像计算。"""
    def __init__(self, out, maximum=8):
        self.out = Path(out)
        self.maximum = maximum
        self.pending = OrderedDict()
        self.paths = []
        self.epoch = 0
        self.last_start = None
        self.stats = dict(epochs=1, complete_groups=0, incomplete_groups=0,
                          invalid_groups=0, evicted_groups=0, peak_pending_groups=0,
                          observed_source_frame_gaps=0, packets=0)
        self.rejections = (self.out / 'rejected_groups.jsonl').open('w', encoding='utf-8')

    def reject(self, key, reason, invalid=False):
        group = self.pending.pop(key)
        self.stats['invalid_groups' if invalid else 'incomplete_groups'] += 1
        count = group.get('ASG1', {}).get('count')
        missing = [name for name in ('AIF1', 'ASG1', 'AER1') if name not in group]
        if count is not None:
            missing.extend(f'ACR2[{i}]' for i in range(count) if i not in group['chars'])
        row = dict(epoch=key[0], frame_id=key[1], reason=reason, missing=missing,
                   received_char_indices=sorted(group['chars']))
        self.rejections.write(json.dumps(row) + '\n')

    def feed(self, packet):
        magic = packet['magic']
        # 两个版本共用分组槽，保留包内magic以选择独立定位参考核验。
        if magic in ('ASG2','ASG3','ASG4','ASG5'):magic='ASG1'
        fid = packet['frame_id']
        self.stats['packets'] += 1
        if magic == 'AIF1':
            # 模式复位后 frame_id 可归零；先丢弃前一轮残包，禁止跨轮拼帧。
            if self.last_start is not None and fid < self.last_start:
                for key in list(self.pending):
                    self.reject(key, 'frame_id_reset')
                self.epoch += 1
                self.stats['epochs'] += 1
            elif self.last_start is not None and fid > self.last_start:
                self.stats['observed_source_frame_gaps'] += fid - self.last_start - 1
            self.last_start = fid
        key = (self.epoch, fid)
        if key not in self.pending:
            if len(self.pending) >= self.maximum:
                self.reject(next(iter(self.pending)), 'pending_limit')
                self.stats['evicted_groups'] += 1
            self.pending[key] = dict(chars={})
            self.stats['peak_pending_groups'] = max(self.stats['peak_pending_groups'], len(self.pending))
        group = self.pending[key]
        if magic == 'ACR2':
            index = packet['char_index']
            if index in group['chars']:
                self.reject(key, 'duplicate_character', invalid=True)
                return
            group['chars'][index] = packet
        else:
            if magic in group:
                self.reject(key, 'duplicate_packet_' + magic, invalid=True)
                return
            group[magic] = packet
        if packet.get('status', 0):
            self.reject(key, 'hardware_status_' + str(packet['status']), invalid=True)
            return
        if not all(name in group for name in ('AIF1', 'ASG1', 'AER1')):
            return
        count = group['ASG1']['count']
        if group['AER1']['completed_chars'] != count:
            self.reject(key, 'completed_count_mismatch', invalid=True)
            return
        if any(index >= count for index in group['chars']):
            self.reject(key, 'unexpected_character_index', invalid=True)
            return
        if set(group['chars']) != set(range(count)):
            return
        folder = self.out / 'frames' / f'e{self.epoch:03d}_f{fid:010d}'
        # 同一轮重复完整帧不能覆盖已有证据。
        if folder.exists():
            self.reject(key, 'duplicate_complete_frame', invalid=True)
            return
        folder.mkdir(parents=True)
        group['epoch'] = self.epoch
        save_json(folder / 'packets.json', group)
        self.paths.append(folder)
        self.stats['complete_groups'] += 1
        del self.pending[key]

    def finish(self):
        for key in list(self.pending):
            self.reject(key, 'capture_ended')
        self.rejections.close()


