"""Registered four-mode quality gate. No profile is published on FAIL/MISSING."""
from pathlib import Path
import argparse
import itertools
import json
import math
import re
import subprocess
import sys
import numpy as np
from PIL import Image, ImageDraw
from . import dataset as ds
from .reference import fixed_layers, enhance_fixed, filter_fixed


_EXECUTION_REQUIRED = ('model/__init__.py','model/dataset.py','model/evaluate.py','model/reference.py',
                       'tests/test_reference.py','tests/test_evaluation.py')


def _execution_source_hashes(root):
    project = Path(root)/'stream_video_enhance'
    paths = {project/name for name in _EXECUTION_REQUIRED}
    for directory in ('model','tests'):
        paths.update((project/directory).rglob('*.py'))
    try:
        return {p.relative_to(root).as_posix():ds.sha(p.read_bytes()) for p in sorted(paths)}
    except FileNotFoundError as exc:
        raise ValueError('Missing execution source: '+str(exc.filename)) from exc


def _reject_dirty_execution_sources(root, paths):
    status = subprocess.run(['git','status','--porcelain','-z','--untracked-files=all','--',*paths],
                            cwd=root,capture_output=True,check=True)
    if status.stdout:
        raise ValueError('Dirty or untracked execution source; commit all execution Python sources before evaluation')


def capture_execution_sources(root=ds.ROOT):
    """Bind entry bytes to a committed revision before any model filtering."""
    root = Path(root)
    commit = subprocess.run(['git','rev-parse','HEAD'],cwd=root,capture_output=True,text=True,check=True).stdout.strip()
    hashes = _execution_source_hashes(root)
    _reject_dirty_execution_sources(root, list(hashes))
    for name, digest in hashes.items():
        committed = subprocess.run(['git','show',commit+':'+name],cwd=root,capture_output=True)
        if committed.returncode or ds.sha(committed.stdout)!=digest:
            raise ValueError('Uncommitted or mismatched execution source: '+name)
    bundle = dict(commit=commit,source_sha256=hashes)
    verify_execution_sources(bundle,root)
    return bundle


def verify_execution_sources(bundle, root=ds.ROOT):
    """Keep entry identity stable; unrelated documentation commits may advance HEAD."""
    root = Path(root)
    current = _execution_source_hashes(root)
    if current != bundle['source_sha256']:
        raise ValueError('Changed execution source bytes or inventory during evaluation; publication forbidden')
    _reject_dirty_execution_sources(root, list(current))


def _mask_values(image, mask):
    image, mask = np.asarray(image, dtype=float), np.asarray(mask, dtype=bool)
    if image.shape != mask.shape or not mask.any():
        raise ValueError('Mask must match image and contain pixels')
    return image[mask]


def psnr(reference, actual):
    a, b = np.asarray(reference, dtype=float), np.asarray(actual, dtype=float)
    if a.shape != b.shape or not a.size:
        raise ValueError('PSNR requires equal nonempty shapes')
    mse = float(np.mean((a-b)**2))
    return float('inf') if mse == 0 else 10*math.log10(255**2/mse)


def contrast(image, foreground_mask, background_mask):
    return abs(float(_mask_values(image, foreground_mask).mean())-float(_mask_values(image, background_mask).mean()))


def new_clipping(raw, out, mask):
    raw, out = np.asarray(raw), np.asarray(out)
    _mask_values(raw, mask)
    if raw.shape != out.shape:
        raise ValueError('Clip arrays must match')
    return float(np.mean(((raw > 0)&(raw < 255)&((out == 0)|(out == 255)))[mask]))


def temporal_noise(frames, mask):
    frames = np.asarray(frames, dtype=float)
    if frames.ndim != 3 or frames.shape[0] < 2:
        raise ValueError('Temporal noise requires multiple frames')
    return float(_mask_values(frames.std(axis=0, ddof=0), mask).mean())


def aggregate_status(checks, required_checks=None):
    if required_checks:
        checks = {**checks, **{key: dict(checks.get(key, {'status':'MISSING'}), required=True)
                               for key in required_checks}}
    statuses = [v.get('status', 'MISSING') for v in checks.values() if v.get('required', True)]
    return 'FAIL' if 'FAIL' in statuses else ('PASS' if statuses and all(s=='PASS' for s in statuses) else 'MISSING')


def publish_profile(model_dir, checks, config, required_checks=None):
    if aggregate_status(checks, required_checks) != 'PASS':
        return False
    (Path(model_dir)/'profile.json').write_text(json.dumps(dict(profile_id=1, **config), indent=2)+'\n', encoding='utf-8')
    return True


def registered_candidates(reg):
    grid = reg['candidates']
    finegain = reg.get('experiment') == 'finegain-v3'
    if finegain:
        ds.validate_finegain_registration(reg)
    for epsilon, td, te, ge in itertools.product(grid['epsilon'], grid['denoise_threshold'],
                                               grid['enhance_threshold'], grid['enhance_gain']):
        legal_gains = grid['enhance_gain'] if finegain else (384,448,512)
        if epsilon not in (16,64,256,1024) or td not in (2,4,8) or te not in (2,4) or ge not in legal_gains or grid['limit'] != 16:
            raise ValueError('Registration contains an unsupported candidate')
        yield dict(epsilon=epsilon, T_D=td, T_E=te, G_E=ge, L=grid['limit'])


def select_candidate(reg, candidates):
    """Rank only the registered tuning outcomes; old replays stay first-feasible."""
    finegain = reg.get('experiment') == 'finegain-v3'
    if finegain:
        ds.validate_finegain_registration(reg)
    feasible = [i for i,c in enumerate(candidates) if c['status']=='PASS' and
                (not finegain or aggregate_status(c['checks'])=='PASS')]
    index = feasible[0] if feasible else 0
    margins = {}
    if finegain and feasible:
        for i in feasible:
            margins[i] = min(candidates[i]['checks']['primary_'+key]['value']
                             for key in reg['primary_enhancement'][reg['selection_policy']['split']])
        index = min(feasible, key=lambda i:(-margins[i],*[candidates[i]['config'][k]
                                                         for k in reg['selection_policy']['tie_break']]))
    selected = dict(index=index,config=candidates[index]['config'],tuning_feasible=bool(feasible),
                    role='selected_on_tuning' if feasible else 'diagnostic_only_no_feasible_tuning_candidate')
    if finegain:
        selected['selection_margin'] = margins.get(index)
    return selected


def real_image_class_check(reg, arrays):
    present, regions = set(), []
    for case in reg['cases']:
        region_class = case.get('region_class')
        if case['category'] != 'real' or region_class not in ('flat','text','texture'):
            continue
        image = arrays.get(case['id'])
        masks = [arrays.get(case[k]) for k in ('foreground','background')]
        valid = image is not None and all(m is not None and m.shape==image.shape and crop(m).any() for m in masks)
        if valid:
            present.add(region_class)
            regions.append(dict(id=case['id'], region_class=region_class,
                                foreground_pixels=int(crop(masks[0]).sum()), background_pixels=int(crop(masks[1]).sum())))
    return dict(status='PASS' if present=={'flat','text','texture'} else 'MISSING',
                classes_present=sorted(present), classes_required=['flat','text','texture'], regions=regions,
                explanation='Explicit registered photographic regions and nonempty fixed masks; public photos are not OV7670 captures. No clean photographic reference or PSNR.')


def crop(a):
    return a[4:-4, 4:-4]


def _outputs(image, config, cache=None, key=None):
    cachekey = (key, config['epsilon'])
    if cache is not None and cachekey in cache:
        raw, base = cache[cachekey]
    else:
        layers = fixed_layers(image, config['epsilon'])
        raw, base = layers['raw'], layers['base_q8']
        if cache is not None:
            cache[cachekey] = raw, base
    return dict(RAW=raw, BASE=((base+128)>>8).astype(np.uint8),
                DENOISE=enhance_fixed(raw, base, config['T_D'], 256),
                ENHANCE=enhance_fixed(raw, base, config['T_E'], config['G_E']))


def _check(value, condition, **details):
    return dict(status='PASS' if condition else 'FAIL', value=value, **details)


def assess(reg, arrays, split, config, cache=None, full=False):
    rows, checks = [], {}
    for case in reg['cases']:
        if case['split'] != split:
            continue
        outputs = _outputs(arrays[case['id']], config, cache, case['id'])
        fg, bg = crop(arrays[case['foreground']]), crop(arrays[case['background']])
        clean = crop(arrays[case['clean']]) if case['clean'] else None
        raw = outputs['RAW']
        metric_mask = crop(arrays[case['region_mask']]) if 'region_mask' in case else np.ones_like(raw, bool)
        row = dict(id=case['id'], category=case['category'], sigma=case['sigma'], seed=case['seed'], modes={})
        if case['category'] == 'real':
            row.update({k:case[k] for k in ('source_id','region_class','region_box') if k in case})
            row['region_pixels'] = int(metric_mask.sum())
        for mode, out in outputs.items():
            c = contrast(out, fg, bg)
            metric = dict(contrast=c, contrast_vs_raw=c/contrast(raw, fg, bg) if contrast(raw, fg, bg) else None,
                          spatial_std=float(out[metric_mask].std()), new_clipping=new_clipping(raw, out, metric_mask),
                          mean=float(out[metric_mask].mean()))
            if clean is not None:
                p = psnr(clean, out)
                metric.update(psnr_db=p if math.isfinite(p) else None, psnr_infinite=math.isinf(p), bias=float(out.astype(float).mean()-clean.mean()))
            if case['category'] == 'step' and case['sigma'] == 0:
                outside = np.maximum(32-out.astype(float), out.astype(float)-224)
                metric['overshoot'] = max(0., float(outside.max()))
                # Number of affected pixels and perpendicular extent in pixels.
                # Straight edge profile spans y or x; diagonal distance uses sqrt2.
                bad = outside > 0
                metric['halo_pixels'] = int(bad.sum())
                yy, xx = np.indices(out.shape)
                direction = case['id'].split('step_')[1].split('_')[0]
                signed = xx if direction == 'vertical' else yy if direction == 'horizontal' else (xx-yy)/np.sqrt(2)
                metric['halo_width_pixels'] = float(signed[bad].max()-signed[bad].min()+1) if bad.any() else 0.
            row['modes'][mode] = metric
        rows.append(row)
    flat8 = [r for r in rows if r['category']=='flat' and r['sigma']==8]
    improvements = [r['modes']['DENOISE']['psnr_db']-r['modes']['RAW']['psnr_db'] for r in flat8]
    bias = max(abs(r['modes']['DENOISE']['bias']) for r in flat8)
    checks['flat_sigma8_psnr'] = _check(float(np.mean(improvements)), np.mean(improvements)>=1, threshold_min_db=1, all_seed_db=improvements)
    checks['flat_mean_bias'] = _check(bias, bias<=1, threshold_max=1)
    lines = [r for r in rows if r['category']=='line' and r['sigma']==0]
    ratios = [r['modes']['DENOISE']['contrast_vs_raw'] for r in lines]
    checks['clean_line_retention'] = _check(float(np.mean(ratios)), np.mean(ratios)>=.8, threshold_min=.8,
                                         worst_id=lines[int(np.argmin(ratios))]['id'], worst_ratio=min(ratios), all_ratios=ratios)
    steps = [r for r in rows if r['category']=='step' and r['sigma']==0]
    default_far = min(r['modes']['DENOISE']['contrast_vs_raw'] for r in steps)
    default_over = max(r['modes']['DENOISE']['overshoot'] for r in steps)
    enhance_over = max(r['modes']['ENHANCE']['overshoot'] for r in steps)
    checks['clean_step_far'] = _check(default_far, default_far>=.95, threshold_min=.95)
    checks['default_step_overshoot'] = _check(default_over, default_over<=2, threshold_max=2)
    checks['enhance_step_overshoot'] = _check(enhance_over, enhance_over<=2, threshold_max=2)
    for key in reg['primary_enhancement'][split]:
        row = next(r for r in rows if r['id']==key)
        ratio = row['modes']['ENHANCE']['contrast_vs_raw']
        checks['primary_'+key] = _check(ratio, ratio>=1.05, threshold_min=1.05, four_modes=row['modes'])
    for sigma in (2,4,8):
        selected = [r for r in rows if r['category']=='flat' and r['sigma']==sigma]
        ratios = [r['modes']['ENHANCE']['spatial_std']/r['modes']['RAW']['spatial_std'] for r in selected]
        checks[f'flat_noise_sigma{sigma}'] = _check(max(ratios), max(ratios)<=1.1, threshold_max=1.1,
                                                  all_seed_ratios=ratios, worst_id=selected[int(np.argmax(ratios))]['id'])
    details = [r for r in rows if r['category'] in ('line','text','texture')]
    clips = [r['modes']['ENHANCE']['new_clipping'] for r in details]
    checks['new_clipping'] = _check(max(clips), max(clips)<=.001, threshold_max=.001, worst_id=details[int(np.argmax(clips))]['id'])
    sequence_metrics = {}
    for seq in reg['sequences']:
        if seq['split'] != split:
            continue
        # Moving/exposure sequences have no gate threshold. Evaluate only once
        # for the fixed selected configuration, never tune using their outputs.
        if not full and seq['kind'] in ('moving','exposure_simulated'):
            continue
        stacks = {mode:[] for mode in ('RAW','BASE','DENOISE','ENHANCE')}
        for i, frame in enumerate(arrays[seq['id']]):
            out = _outputs(frame, config, cache, seq['id']+str(i))
            for mode in stacks:
                stacks[mode].append(out[mode])
        metrics = {}
        for mode, frames in stacks.items():
            frames = np.stack(frames)
            mask = np.ones(frames.shape[1:], bool)
            metrics[mode] = dict(temporal_std=temporal_noise(frames, mask),
                                 identical=bool(np.all(frames==frames[0])),
                                 mean_frame_delta=float(np.abs(np.diff(frames.astype(float), axis=0)).mean()),
                                 step_overshoot=max(0., float(np.maximum(32-frames.astype(float), frames.astype(float)-224).max())) if seq['kind']=='moving' else None)
        sequence_metrics[seq['id']] = metrics
        if seq['kind']=='repeated':
            checks['repeated64_exact'] = _check({m:x['identical'] for m,x in metrics.items()}, all(x['identical'] for x in metrics.values()))
        if seq['kind']=='temporal_noise':
            ratio = metrics['ENHANCE']['temporal_std']/metrics['RAW']['temporal_std']
            checks['temporal64_noise'] = _check(ratio, ratio<=1.1, threshold_max=1.1, four_modes=metrics)
    return dict(config=config, checks=checks, status=aggregate_status(checks),
                cases=rows if full else None, sequences=sequence_metrics if full else None)


def _visuals(report_dir, reg, arrays, result):
    config = result['selected_candidate']['config']
    chosen = reg['primary_enhancement']['holdout'] + ['holdout_line_vertical_1_s8_n0', 'holdout_text_low_s8_n0',
              'holdout_texture_p8_a16_s8_n0', 'holdout_step_vertical_clean', 'holdout_highlights_clean']
    chosen += [c['id'] for c in reg['cases'] if c['category']=='real']
    for category in ('line','text','texture'):
        rows=[r for r in result['holdout']['cases'] if r['category']==category]
        chosen.append(min(rows, key=lambda r:r['modes']['ENHANCE']['contrast_vs_raw'])['id'])
    for key in chosen:
        if key not in arrays:
            continue
        outputs = _outputs(arrays[key], config)
        h,w = next(iter(outputs.values())).shape
        scale = 2 if w<200 else 1
        sheet = Image.new('RGB', (w*scale*4, h*scale+40), 'white')
        draw = ImageDraw.Draw(sheet)
        for i,(mode,out) in enumerate(outputs.items()):
            sheet.paste(Image.fromarray(out).resize((w*scale,h*scale), Image.Resampling.NEAREST).convert('RGB'), (i*w*scale,40))
            draw.text((i*w*scale+4,4), mode, fill='black')
        draw.text((4,22), key, fill='black')
        sheet.save(report_dir/(key+'_four_modes.png'))
    profiles = {}
    for direction in ('vertical','horizontal','diagonal'):
        key = 'holdout_step_'+direction+'_clean'
        outputs = _outputs(arrays[key], config)
        # A horizontal edge varies with y: cross it along the middle column.
        # Vertical and diagonal edges use the middle row; the diagonal plot's
        # axis is x pixels, not perpendicular distance (halo metric is separate).
        profiles[direction] = {m:(o[:, o.shape[1]//2] if direction == 'horizontal'
                                  else o[o.shape[0]//2]).tolist() for m,o in outputs.items()}
        chart = Image.new('RGB', (800,360), 'white'); draw = ImageDraw.Draw(chart)
        colors = dict(RAW='black',BASE='blue',DENOISE='green',ENHANCE='red')
        for j,(mode,values) in enumerate(profiles[direction].items()):
            points = [(40+i*720/(len(values)-1),320-v) for i,v in enumerate(values)]
            draw.line(points, fill=colors[mode], width=2)
            draw.text((40+j*160,10), mode, fill=colors[mode])
        sampling = 'middle-column slice, axis=output y' if direction == 'horizontal' else 'middle-row slice, axis=output x'
        draw.text((40,335), direction+' '+sampling+'; gray 0..255', fill='black')
        chart.save(report_dir/('edge_profile_'+direction+'.png'))
    (report_dir/'edge_profiles.json').write_text(json.dumps(profiles,indent=2)+'\n', encoding='utf-8', newline='\n')


def _expanded_report(report_dir, reg, result):
    selected, holdout = result['selected_candidate'], result['holdout']
    allowed = result['status']=='PASS' and result['profile_published']
    finegain = reg.get('experiment')=='finegain-v3'
    count = len(result['candidates'])
    lines = ['# 第15.A节'+('细增益搜索：第三轮独立保留集报告' if finegain else '扩大搜索：第二轮独立保留集报告'), '',
             f"受控模型门槛：**{result['status']}**；发布profile：{'已发布' if result['profile_published'] else '无'}；算法RTL：{'允许进入后续实施' if allowed else '禁止进入'}。", '',
             f"登记提交：`{result['registration_commit']}`；登记SHA256：`{result['registration_sha256']}`。",
             f"输入归档SHA256：`{result['archive_sha256']}`；执行模型提交：`{result['source_model_commit']}`；登记生成模型提交：`{reg['source_model_commit']}`。", '',
             ('用户于2026-10-23授权既有合法范围的软件搜索；本轮仅细化G384…448步长4。公式、位宽、舍入及所有验收阈值保持不变；第一轮24项与第二轮72项FAIL和全部输入/报告字节原样保留。' if finegain else
              '用户于2026-10-23授权保持公式、位宽及RAW+5%阈值，扩至4种ε和G512。首轮reports/model_gate的24项FAIL及归档原样保留；本轮不改写首轮结论。'),
             '真实不同曝光和真实固定曝光64帧验证按授权移至相机集成里程碑，当前均DEFERRED、非本轮必选；不称为PASS。受控PASS只允许开展算法RTL。', '',
             '## 搜索前固定的证据与选择规则', '',
             ('正式候选恰51项：ε1024，T_D2/4/8，T_E4，G_E=list(range(384,449,4))，L16。在全部调参检查PASS的候选中，最大化两项主ENHANCE/RAW对比度比值的最小值；并列时先最低T_D、再最低G_E。没有可行项才用首项诊断。' if finegain else
              '正式候选恰72项：ε16/64/256/1024，T_D2/4/8，T_E2/4，G_E384/448/512，L16；按这些字段升序选择第一个调参可行项。没有可行项才用首项诊断。'),
             ('调参干净图案保留原定义。新保留文字BRAM 2026/Smooth Gain/Video Core，起点(17,9)；纹理(2*x+y+3)%period<period/2，周期4/8、振幅16/32；两项主例固定为文字和周期4振幅32。' if finegain else
              '调参干净图案保留原定义。新保留集文字为Core VGA/Gain 512/Pixel 2026，起点(7,11)；纹理为(x+2y+1)%period<period/2的斜向条纹，周期4/8、振幅16/32；两项主例固定为文字和周期4振幅32。'),
             ('两个新主输入逐字节不同于前两轮全部二维U8数组与本轮全部调参图，比较在登记提交前完成。所有噪声/时间噪声使用SeedSequence entropy2026102303，按split/pattern/sigma/seed分流。' if finegain else
              '两个新主输入逐字节不同于首轮全部二维U8数组与调参主图。所有噪声/时间噪声使用SeedSequence entropy2026102302，按split/pattern/sigma/seed分流；不只移动旧保留图的相位。'),
             '平场、细线、阶跃、渐变、棋盘、脉冲、高光及移动阶跃是复用的规范压力图案（REUSED_NOT_NOVEL_HOLDOUT_EVIDENCE），不冒称新增独立保留证据。统一每边裁4像素，输入与掩膜哈希全在registration.json。',
             f"{count}项中调参可行数：{sum(c['status']=='PASS' for c in result['candidates'])}；固定选择：`{selected['config']}`；角色：{selected['role']}。",
             '选择完全基于调参集；新保留集仅评所选一项一次，不另跑旧参数或探索参数，不按保留集排名。', '',
             '## 必选门槛与延期项', '', '| 检查 | 必选 | 状态 | 值或证据 |', '|---|---|---|---|']
    for key, check in result['checks'].items():
        lines.append(f"| {key} | {'是' if check.get('required',True) else '否'} | {check['status']} | {check.get('value',check.get('explanation','见JSON'))} |")
    lines += ['', f'## 全部{count}项调参结果', '', '| ε | T_D | T_E | G_E | 文字/RAW | 纹理/RAW | 结果 | 失败项 |', '|---|---|---|---|---|---|---|---|']
    for candidate in result['candidates']:
        cfg, cc = candidate['config'], candidate['checks']
        values = [cc['primary_'+key]['value'] for key in reg['primary_enhancement']['tuning']]
        failed = ', '.join(k for k,v in cc.items() if v['status']!='PASS') or '无'
        lines.append(f"| {cfg['epsilon']} | {cfg['T_D']} | {cfg['T_E']} | {cfg['G_E']} | {values[0]:.6f} | {values[1]:.6f} | {candidate['status']} | {failed} |")
    lines += ['', '## 新保留集四模式与代价', '', '| 主案例 | RAW对比度 | BASE | DENOISE | ENHANCE | ENHANCE/RAW |', '|---|---|---|---|---|---|']
    for key in reg['primary_enhancement']['holdout']:
        row = next(r for r in holdout['cases'] if r['id']==key)
        ms = row['modes']
        lines.append('| '+key+' | '+' | '.join(f"{ms[m]['contrast']:.6f}" for m in ('RAW','BASE','DENOISE','ENHANCE'))+f" | {ms['ENHANCE']['contrast_vs_raw']:.6f} |")
    lines += ['', '| σ | RAW平均PSNR | BASE | DENOISE | ENHANCE |', '|---|---|---|---|---|']
    for sigma in (2,4,8,16):
        rows = [r for r in holdout['cases'] if r['category']=='flat' and r['sigma']==sigma]
        lines.append(f'| {sigma} | '+' | '.join(f"{np.mean([r['modes'][m]['psnr_db'] for r in rows]):.6f}" for m in ('RAW','BASE','DENOISE','ENHANCE'))+' |')
    lines += ['', '最差案例覆盖全部登记干净/加噪细节，不用于换参数。', '', '| 类别 | 最差输入 | ENHANCE/RAW | 新截断比例 |', '|---|---|---|---|']
    for category in ('line','text','texture'):
        rows = [r for r in holdout['cases'] if r['category']==category]
        worst = min(rows,key=lambda r:r['modes']['ENHANCE']['contrast_vs_raw'])
        lines.append(f"| {category} | {worst['id']} | {worst['modes']['ENHANCE']['contrast_vs_raw']:.6f} | {worst['modes']['ENHANCE']['new_clipping']:.6f} |")
    lines += ['', '各模式完整对比度/噪声/偏移/截断在metrics.json。PSNR只用于已知合成干净参考；零MSE用null和psnr_infinite表示。σ16作为压力测试保留全部5种子。',
              '阶跃JSON含越界幅值、像素数、垂直宽度；PNG和edge_profiles.json含三方向剖面。水平边沿中间列沿y采样；垂直/斜边沿中间行沿x采样；斜边图横轴不是垂直距离。',
              '64帧的噪声指标先逐像素沿时间取总体标准差、再在固定平场掩膜平均；移动/模拟曝光序列另报帧差与移动光晕，未冒充真实曝光。', '',
              '## 真实照片固定区域', '',
              '公开camera.png登记裁剪(0,16,512,496)，sky原坐标(0,0,130,65)对应登记(0,0,130,49)；grass原坐标(350,300,500,480)对应登记(350,284,500,464)。前者为flat、后者texture；text.png为printed text；实际OV7670石墨图为纸面/石墨笔画text补充。',
              'flat区域按横向两半定义固定掩膜，其余区域以原始灰度的0.3/0.7分位定义背景/前景；全部mask搜索前固定并登记，gate比较flat/text/texture类别集合和有效非空mask，不按照片文件数。',
              '真实图不假设干净参考、不计算PSNR；下面只报告固定区域的观测统计。来源/授权/源字节哈希在sources/provenance.json及registration.json；公开照片不是本板摄像头采集。', '',
              '| 区域/类 | 模式 | 对比度 | 空间标准差 | 均值 | 新截断 |', '|---|---|---|---|---|---|']
    for row in holdout['cases']:
        if row['category']=='real':
            for mode, m in row['modes'].items():
                lines.append(f"| {row['id']} / {row.get('region_class')} | {mode} | {m['contrast']:.6f} | {m['spatial_std']:.6f} | {m['mean']:.6f} | {m['new_clipping']:.6f} |")
    lines += ['', '## 证据边界与后续', '', *['- '+gap for gap in reg['evidence_gaps']], '',
              '本轮无算法RTL、综合、布局布线或实板证据。受控门槛通过后执行第16节关键模块/延迟冻结与仿真计划；实际曝光、固定曝光视频及相机细文字/自然纹理仍需相机集成补验。若本轮FAIL，保留全部证据并停止算法RTL，按第17节讨论必要调整。', '',
              '## 复现', '', '```powershell',
              'python -m stream_video_enhance.model.evaluate --experiment '+reg['experiment']+' --register --report-dir stream_video_enhance/reports/'+report_dir.name,
              '# 仅用于新空目录；登记文件、输入归档、模型代码先提交，再执行搜索。现有登记不可覆盖。',
              'python -m stream_video_enhance.model.evaluate --run --report-dir stream_video_enhance/reports/'+report_dir.name,
              'python -m unittest discover -s stream_video_enhance/tests -v', '```', '',
              '受控必选项全部PASS才返回0和发布可追溯profile；FAIL/MISSING返回1，输入/登记无效返回2。完整执行输出见logs，数值回归见numerical_tests.txt。']
    (report_dir/'report.md').write_text('\n'.join(lines)+'\n',encoding='utf-8',newline='\n')


def run(report_dir=ds.DEFAULT_REPORT):
    report_dir=Path(report_dir)
    execution_sources = capture_execution_sources()
    reg, arrays = ds.load_registration(report_dir)
    # Require an actual committed registration, not merely a generated timestamp.
    relative = (report_dir/'registration.json').resolve().relative_to(ds.ROOT).as_posix()
    tracked = subprocess.run(['git','log','-1','--format=%H','--',relative], cwd=ds.ROOT, capture_output=True,text=True,check=True).stdout.strip()
    if not tracked:
        raise ValueError('Commit the registration before candidate search')
    diff = subprocess.run(['git','diff','HEAD','--',relative, str(report_dir/'inputs.npz')], cwd=ds.ROOT,capture_output=True,text=True,check=True)
    if diff.stdout:
        raise ValueError('Registration/input archive differs from committed bytes')
    numerical = subprocess.run([sys.executable,'-m','unittest','discover','-s','stream_video_enhance/tests','-p','test_reference.py','-v'],
                               cwd=ds.ROOT,capture_output=True,text=True)
    (report_dir/'numerical_tests.txt').write_text(numerical.stdout+numerical.stderr,encoding='utf-8',newline='\n')
    candidates, cache = [], {}
    for config in registered_candidates(reg):
        candidates.append(assess(reg,arrays,'tuning',config,cache))
    feasible=[i for i,c in enumerate(candidates) if c['status']=='PASS']
    selected=select_candidate(reg,candidates)
    # The holdout is assessed once, after the deterministic tuning choice.
    holdout=assess(reg,arrays,'holdout',selected['config'],{},full=True)
    checks=dict(holdout['checks'])
    checks['tuning_feasible']=_check(len(feasible), bool(feasible), candidate_count=len(candidates))
    checks['numerical_model']=dict(status='PASS' if numerical.returncode==0 else 'FAIL', command='python -m unittest discover -s stream_video_enhance/tests -p test_reference.py -v',
                                   log='numerical_tests.txt', scope='all constants/modes/epsilon/bounds, variance/division, 288 VGA cases max error<=1, histogram/MAE/RMSE')
    checks['real_image_classes']=real_image_class_check(reg, arrays) if reg.get('experiment') in ('expanded-v2','finegain-v3') else dict(
        status='PASS' if len([c for c in reg['cases'] if c['category']=='real'])>=3 else 'MISSING',
        explanation='Legacy original-v1 replay only: historical file-count criterion. Expanded-v2 requires explicit registered flat/text/texture regions and nonempty masks.')
    checks['real_exposure_classes']=dict(status='MISSING', explanation=reg['evidence_gaps'][0])
    checks['camera_video_evidence']=dict(status='MISSING', explanation=reg['evidence_gaps'][1], required=False)
    checks['future_rtl_bit_exact']=dict(status='DEFERRED', required=False, explanation='Only applicable after model gate PASS; no algorithm RTL exists.')
    expanded = reg.get('experiment') in ('expanded-v2','finegain-v3')
    for key, policy in reg.get('evidence_policy', {}).items():
        checks[key] = dict(checks.get(key, {}), **policy)
    required_checks = reg.get('required_checks')
    verify_execution_sources(execution_sources)
    if expanded:
        source_model_commit = execution_sources['commit']
        result = dict(schema=2, experiment=reg['experiment'], registration_commit=tracked,
                      registration_sha256=ds.sha((report_dir/'registration.json').read_bytes()),
                      archive_sha256=reg['archive_sha256'], source_model_commit=source_model_commit,
                      execution_sources=execution_sources,
                      registered_generator_commit=reg['source_model_commit'], status=aggregate_status(checks,required_checks),
                      checks=checks, required_checks=required_checks, selected_candidate=selected,
                      candidates=candidates, holdout=holdout, holdout_configurations_evaluated=1,
                      profile_published=False, evidence_gaps=reg['evidence_gaps'])
        if reg['experiment']=='finegain-v3':
            result['selection_policy']=reg['selection_policy']
            result['failure_frontier']=[dict(config=c['config'],
                failed_checks=[k for k,v in c['checks'].items() if v['status']!='PASS'],
                minimum_primary_ratio=min(c['checks']['primary_'+key]['value'] for key in reg['primary_enhancement']['tuning']))
                for c in candidates if c['status']!='PASS']
        if result['status'] == 'PASS':
            profile = dict(**selected['config'], experiment=reg['experiment'],
                           registration_commit=tracked, registration_sha256=result['registration_sha256'],
                           input_archive_sha256=reg['archive_sha256'], source_model_commit=source_model_commit,
                           execution_sources=execution_sources,
                           registered_generator_commit=reg['source_model_commit'],
                           required_checks={key:checks[key]['status'] for key in required_checks},
                           evidence_policy=reg['evidence_policy'], applicable_scope='Controlled registered model gate; camera exposure/real video validation DEFERRED')
            result['profile_published'] = publish_profile(Path(__file__).parent,checks,profile,required_checks)
        (report_dir/'metrics.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8',newline='\n')
        _visuals(report_dir,reg,arrays,result)
        _expanded_report(report_dir,reg,result)
        print(json.dumps(dict(status=result['status'],tuning_feasible=len(feasible),candidate_count=len(candidates),
                              holdout_configurations_evaluated=1,selected=selected,profile_published=result['profile_published'],
                              failures=[k for k,v in checks.items() if v.get('required',True) and v['status']!='PASS']),ensure_ascii=False))
        return 0 if result['status']=='PASS' else 1
    exploratory_config = dict(selected['config'], G_E=512)
    exploratory = assess(reg, arrays, 'holdout', exploratory_config, {}, full=True)
    result=dict(schema=1, registration_commit=tracked, registration_sha256=ds.sha((report_dir/'registration.json').read_bytes()),
                archive_sha256=reg['archive_sha256'], status=aggregate_status(checks), checks=checks,
                selected_candidate=selected, candidates=candidates, holdout=holdout,
                old_nonpublication_control=dict(config=dict(epsilon=64,T_D=4,T_E=4,G_E=320,L=16),
                                               holdout=assess(reg,arrays,'holdout',dict(epsilon=64,T_D=4,T_E=4,G_E=320,L=16),{},full=True)),
                exploratory_legal_gain512=dict(role='POST_GATE_EXPLORATORY_ONLY_NOT_REGISTERED_NOT_QUALIFYING',
                                               reason='Official search failed enhancement; test whether legal gain ceiling alone addresses it. Does not alter official selection/gate.',
                                               assessment=exploratory),
                profile_published=False, evidence_gaps=reg['evidence_gaps'])
    # Infinity is represented as null plus explicit psnr_infinite, strict JSON.
    (report_dir/'metrics.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8',newline='\n')
    _visuals(report_dir,reg,arrays,result)
    failures={k:v for k,v in checks.items() if v['status'] in ('FAIL','MISSING')}
    lines=['# 第15.A节模型质量门槛报告', '', f"总结果：**{result['status']}**；发布profile：无；算法RTL：禁止进入。", '',
           f"登记提交：`{tracked}`；登记SHA256：`{result['registration_sha256']}`。", f"输入归档SHA256：`{reg['archive_sha256']}`。", '',
           '调参前固定两个独立主增强图案：细文字和周期4/振幅32纹理；保留集改变文字内容、位置和纹理几何。输入96×128；照片保留登记裁剪尺寸；统一裁边4像素。',
           '噪声每类σ=2/4/8/16、种子0…4；调参/保留使用独立PCG64 seed stream。全部输入、掩膜、64帧序列均已归档并逐数组SHA256校验。', '',
           f"搜索{len(candidates)}组共享ε候选，可行候选数：{len(feasible)}。固定选择：`{selected['config']}`，角色：{selected['role']}。",
           '若无调参可行项，使用预登记排序第一项作失败诊断；未根据保留集挑选胜者。旧g=1.25/T=4另存非发布对照。', '',
           '| 检查 | 状态 | 值 |', '|---|---|---|']
    for key,check in checks.items():
        lines.append(f"| {key} | {check['status']} | {check.get('value',check.get('explanation','见JSON/日志'))} |")
    lines += ['', '## 全部调参候选', '', '| ε | T_D | T_E | G_E | 主文字/RAW | 主纹理/RAW | 失败项 |', '|---|---|---|---|---|---|---|']
    for candidate in candidates:
        cfg, cc = candidate['config'], candidate['checks']
        primary_values=[cc['primary_'+key]['value'] for key in reg['primary_enhancement']['tuning']]
        failed=', '.join(k for k,v in cc.items() if v['status']=='FAIL')
        lines.append(f"| {cfg['epsilon']} | {cfg['T_D']} | {cfg['T_E']} | {cfg['G_E']} | {primary_values[0]:.6f} | {primary_values[1]:.6f} | {failed} |")
    balanced=next(c for c in candidates if c['config']==dict(epsilon=256,T_D=2,T_E=2,G_E=384,L=16))
    stronger=next(c for c in candidates if c['config']==dict(epsilon=256,T_D=2,T_E=2,G_E=448,L=16))
    bc, sc=balanced['checks'], stronger['checks']
    lines += ['', 'ε=256也未解决两项目标的权衡（以下仅引用调参数据，不更换保留集诊断参数）：',
              f"- T_E=2/G_E=384：纹理/RAW={bc['primary_tuning_texture_p4_a32_clean']['value']:.6f}；σ8最差空间噪声比={bc['flat_noise_sigma8']['value']:.6f}；时间噪声比={bc['temporal64_noise']['value']:.6f}。纹理未增强，噪声也略过1.1门槛。",
              f"- T_E=2/G_E=448：纹理/RAW={sc['primary_tuning_texture_p4_a32_clean']['value']:.6f}（仍小于1.05）；σ8空间噪声比={sc['flat_noise_sigma8']['value']:.6f}、时间噪声比={sc['temporal64_noise']['value']:.6f}。增加增益加大噪声代价。",
              '- T_E=4可控制噪声，但全部ε=256候选仍未同时达到两项主增强门槛。T_D只控制DENOISE，不改变ENHANCE的失败。']
    lines += ['', '## 保留集定量摘要', '', '| 主案例 | RAW | BASE | DENOISE | ENHANCE | ENHANCE变化 |', '|---|---|---|---|---|---|']
    for key in reg['primary_enhancement']['holdout']:
        row=next(r for r in holdout['cases'] if r['id']==key)
        ms=row['modes']
        lines.append('| '+key+' | '+' | '.join(f"{ms[m]['contrast']:.6f}" for m in ('RAW','BASE','DENOISE','ENHANCE'))+f" | {(ms['ENHANCE']['contrast_vs_raw']-1)*100:+.3f}% |")
    lines += ['', '| σ | RAW平均PSNR | BASE平均PSNR | DENOISE平均PSNR | ENHANCE平均PSNR |', '|---|---|---|---|---|']
    for sigma in (2,4,8,16):
        rows=[r for r in holdout['cases'] if r['category']=='flat' and r['sigma']==sigma]
        lines.append(f'| {sigma} | '+' | '.join(f"{np.mean([r['modes'][m]['psnr_db'] for r in rows]):.6f}" for m in ('RAW','BASE','DENOISE','ENHANCE'))+' |')
    lines += ['', '下表最差对比度包含全部预登记干净/噪声输入，不用于换参数。', '', '| 类别 | 最差输入 | ENHANCE/RAW | 新截断 |', '|---|---|---|---|']
    for category in ('line','text','texture'):
        rows=[r for r in holdout['cases'] if r['category']==category]
        worst=min(rows,key=lambda r:r['modes']['ENHANCE']['contrast_vs_raw'])
        lines.append(f"| {category} | {worst['id']} | {worst['modes']['ENHANCE']['contrast_vs_raw']:.6f} | {worst['modes']['ENHANCE']['new_clipping']:.6f} |")
    lines += ['', '## 搜索结束后的探索性诊断', '',
              '仅将已选诊断配置G_E改为合法上限512，未加入正式候选集，未据此选保留集胜者，结果不参与正式验收或发布。',
              *[f"- {key}: ENHANCE/RAW={exploratory['checks']['primary_'+key]['value']:.6f}" for key in reg['primary_enhancement']['holdout']],
              '主纹理残差在选定ε下接近死区；单独提高增益不能保证恢复被软阈值消去的细节。具体是否调整参数范围或算法，仍须用户决定。']
    lines += ['', '## 四模式与代价', '', '每个输入RAW/BASE/DENOISE/ENHANCE的对比度、相对RAW比例、空间噪声、均值、PSNR（仅合成干净参考）、均值偏移和新增截断见metrics.json的holdout.cases。',
              '零MSE的PSNR用null和psnr_infinite=true表示。全部σ16和5种子均保留。阶跃包含越界幅值、受影响像素数和宽度；edge_profiles.json/PNG保存三个方向剖面。',
              '剖面采样轴：水平边取输出图像中间列，沿y跨过边缘；垂直边与斜边取中间行，沿x跨过边缘。斜边剖面横轴并非垂直距离。',
              '序列先按固定像素跨64帧取总体标准差，再对固定平坦掩膜取均值；移动与模拟曝光变化另外报告帧差和移动阶跃光晕。它们不冒称真实曝光采集。', '',
              '## 真实证据边界', '',
              'focus_latest第一RAW面板有仓库日志支持：真实OV7670石墨十字。frame545为MODE1 Sobel，phase_contact含帧时序故障，回归合成帧均未冒充真实RAW。',
              'scikit-image v0.25.2 camera/text是公开真实照片，并非OV7670拍摄；授权与文件/像素哈希见registration.json和sources/provenance.json。真实图没有虚构干净参考或PSNR。',
              *['- '+gap for gap in reg['evidence_gaps']], '', '## 最小后续决策', '',
              '先补采固定曝光/增益的实际平坦、细文字、纹理及不同曝光RAW图和64帧序列；若数值门槛仍失败，按规格第17节由用户决定是否调整公式/参数范围/目标。当前不改阈值、不冻结profile、不编写算法RTL。', '',
              '## 复现', '', '```powershell', 'python -m stream_video_enhance.model.evaluate --register',
              '# 审阅并提交registration.json、inputs.npz及生成代码，然后运行',
              'python -m stream_video_enhance.model.evaluate --run',
              'python -m unittest discover -s stream_video_enhance/tests -v', '```',
              '', '质量FAIL/MISSING时--run返回1并保留报告；输入校验/缺登记异常返回2。数值测试日志在numerical_tests.txt。']
    (report_dir/'report.md').write_text('\n'.join(lines)+'\n',encoding='utf-8',newline='\n')
    if result['status']=='PASS':
        verify_execution_sources(execution_sources)
        result['profile_published']=publish_profile(Path(__file__).parent,checks,selected['config'])
        (report_dir/'metrics.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(dict(status=result['status'],tuning_feasible=len(feasible),selected=selected,failures=list(failures)),ensure_ascii=False))
    return 0 if result['status']=='PASS' else 1


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--register',action='store_true'); group.add_argument('--run',action='store_true')
    parser.add_argument('--report-dir',type=Path,default=ds.DEFAULT_REPORT)
    parser.add_argument('--experiment', choices=['original-v1','expanded-v2','finegain-v3'], default='original-v1', help='Registration only; --run consumes the committed registration')
    args=parser.parse_args()
    try:
        if args.register:
            reg=ds.register(args.report_dir, experiment=args.experiment)
            print(json.dumps(dict(registered=len(reg['cases']),arrays=len(reg['arrays']),sha256=reg['archive_sha256'])))
            return 0
        return run(args.report_dir)
    except (ValueError,FileNotFoundError,FileExistsError) as exc:
        print(str(exc),file=sys.stderr); return 2


if __name__=='__main__':
    sys.exit(main())
