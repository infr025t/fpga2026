"""离线整数参考校验：逐框、逐像素、逐分数比较。"""
import json
import zlib

from auto_collect import json_object

CLASSES = b'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'


def verify_frame(folder, model):
    """逐框、逐像素、逐有符号分数及硬件 argmax 全量对照。"""
    import numpy as np
    from segment_ref import segment_frame
    from norm_ref import normalize_frame
    from integer_cnn import logits

    group = json.loads((folder / 'packets.json').read_text(encoding='utf-8'), object_hook=json_object)
    aif, asg, aer = (group[name] for name in ('AIF1', 'ASG1', 'AER1'))
    raw = np.frombuffer(aif['raw'], dtype=np.uint8).reshape(120, 160)
    np.save(folder / 'raw.npy', raw)
    roi = tuple(aif['roi'])
    flags = aif['flags']
    errors = []
    if zlib.crc32(aif['raw']) != aif['raw_crc']:
        errors.append('raw_crc_mismatch')
    if asg['magic'] in ('ASG2','ASG3','ASG4','ASG5'):
        from plate_locator import locate_plate
        detected=locate_plate(raw)
        roi=tuple(detected or (0,0,0,0))
        if tuple(asg['roi'])!=roi:errors.append('located_roi_mismatch')
        if tuple(aif['roi'])!=(0,0,160,120) or flags not in (0,2):errors.append('locator_search_contract')
        seg=segment_frame(raw,roi,flags,skip_prefix=asg['magic'] in ('ASG3','ASG4'),split_touching=asg['magic'] in ('ASG4','ASG5')) if detected else dict(status=0,boxes=[])
    else:
        seg = segment_frame(raw, roi, flags)
    reference_boxes = [tuple(box) for box in seg['boxes']]
    hardware_boxes = [tuple(box) for box in asg['boxes'][:asg['count']]]
    if seg['status'] != 0 or asg['status'] != 0 or aer['status'] != 0:
        errors.append('nonzero_status')
    if hardware_boxes != reference_boxes:
        errors.append('segmentation_boxes_mismatch')
    result = dict(epoch=group['epoch'], frame_id=aif['frame_id'], capture_tick=aif['capture_tick'],
                  roi=roi, flags=flags, hardware_boxes=hardware_boxes, reference_boxes=reference_boxes,
                  reference_segment_status=seg['status'], characters=[], errors=errors,
                  timing=dict(seg_cycles=asg['seg_cycles'], elapsed_cycles=aer['elapsed_cycles']),
                  hardware_counters={k:aer[k] for k in ('bad_captures', 'skipped_frames', 'publisher_dropped')})
    reference_text = []
    hardware_text = []
    norm_hardware, norm_reference, score_hardware, score_reference = [], [], [], []
    for index in range(asg['count']):
        char = group['chars'][str(index)]
        box = tuple(char['box'])
        hw_norm = np.frombuffer(char['norm'], dtype=np.uint8).reshape(32, 24)
        hw_scores = np.asarray(char['scores'], dtype=np.int32)
        # 即使分割框不一致，仍保存硬件归一化及分数；不以硬件框冒充参考分割结果。
        norm_hardware.append(hw_norm)
        score_hardware.append(hw_scores)
        hw_best = int(hw_scores.argmax())
        char_errors = []
        if box != hardware_boxes[index]:
            char_errors.append('character_box_vs_segment_mismatch')
        if char['class_id'] != hw_best or char['ascii'] != CLASSES[hw_best]:
            char_errors.append('hardware_signed_argmax_mismatch')
        hardware_text.append(chr(char['ascii']))
        row = dict(index=index, hardware_box=box, hardware_class_id=char['class_id'],
                   hardware_ascii=char['ascii'], signed_argmax=hw_best, errors=char_errors,
                   norm_cycles=char['norm_cycles'], core_cycles=char['core_cycles'])
        if index < len(reference_boxes):
            ref_norm, meta = normalize_frame(raw, reference_boxes[index], roi, flags)
            ref_scores = np.asarray(logits(ref_norm, model)[0], dtype=np.int32)
            ref_best = int(ref_scores.argmax())
            reference_text.append(chr(CLASSES[ref_best]))
            norm_reference.append(ref_norm)
            score_reference.append(ref_scores)
            row.update(reference_box=reference_boxes[index], reference_class_id=ref_best,
                       normalization_parameters=meta,
                       norm_pixel_mismatches=int(np.count_nonzero(hw_norm != ref_norm)),
                       score_mismatches=int(np.count_nonzero(hw_scores != ref_scores)),
                       max_pixel_error=int(np.max(np.abs(hw_norm.astype(np.int16) - ref_norm.astype(np.int16)))),
                       max_score_error=int(np.max(np.abs(hw_scores.astype(np.int64) - ref_scores.astype(np.int64)))))
            if row['norm_pixel_mismatches']:
                char_errors.append('normalization_mismatch')
            if row['score_mismatches']:
                char_errors.append('scores_mismatch')
            if char['class_id'] != ref_best or char['ascii'] != CLASSES[ref_best]:
                char_errors.append('prediction_mismatch')
        else:
            char_errors.append('no_reference_box')
        if char_errors:
            errors.append(f'character_{index}_mismatch')
        result['characters'].append(row)
    text = aer['text'].decode('ascii')
    result.update(hardware_prediction=''.join(hardware_text), reference_prediction=''.join(reference_text), result_prediction=text)
    if text != result['hardware_prediction'] or text != result['reference_prediction']:
        errors.append('result_text_mismatch')
    result['passed'] = not errors
    np.savez(folder / 'arrays.npz',
             normalized_hardware=np.asarray(norm_hardware, dtype=np.uint8).reshape(-1, 32, 24),
             normalized_reference=np.asarray(norm_reference, dtype=np.uint8).reshape(-1, 32, 24),
             scores_hardware=np.asarray(score_hardware, dtype=np.int32).reshape(-1, 36),
             scores_reference=np.asarray(score_reference, dtype=np.int32).reshape(-1, 36))
    return result


