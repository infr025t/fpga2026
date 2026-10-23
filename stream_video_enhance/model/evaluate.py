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


def aggregate_status(checks):
    statuses = [v['status'] for v in checks.values() if v.get('required', True)]
    return 'FAIL' if 'FAIL' in statuses else ('PASS' if statuses and all(s=='PASS' for s in statuses) else 'MISSING')


def publish_profile(model_dir, checks, config):
    if aggregate_status(checks) != 'PASS':
        return False
    (Path(model_dir)/'profile.json').write_text(json.dumps(dict(profile_id=1, **config), indent=2)+'\n', encoding='utf-8')
    return True


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
        row = dict(id=case['id'], category=case['category'], sigma=case['sigma'], seed=case['seed'], modes={})
        for mode, out in outputs.items():
            c = contrast(out, fg, bg)
            metric = dict(contrast=c, contrast_vs_raw=c/contrast(raw, fg, bg) if contrast(raw, fg, bg) else None,
                          spatial_std=float(out.std()), new_clipping=new_clipping(raw, out, np.ones_like(raw, bool)),
                          mean=float(out.mean()))
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


def run(report_dir=ds.DEFAULT_REPORT):
    report_dir=Path(report_dir)
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
    for epsilon,td,te,ge in itertools.product((64,256),(2,4,8),(2,4),(384,448)):
        config=dict(epsilon=epsilon,T_D=td,T_E=te,G_E=ge,L=16)
        candidates.append(assess(reg,arrays,'tuning',config,cache))
    feasible=[i for i,c in enumerate(candidates) if c['status']=='PASS']
    index=feasible[0] if feasible else 0
    selected=dict(index=index, config=candidates[index]['config'], tuning_feasible=bool(feasible),
                  role='selected_on_tuning' if feasible else 'diagnostic_only_no_feasible_tuning_candidate')
    # The holdout is assessed once, after the deterministic tuning choice.
    holdout=assess(reg,arrays,'holdout',selected['config'],{},full=True)
    checks=dict(holdout['checks'])
    checks['tuning_feasible']=_check(len(feasible), bool(feasible), candidate_count=len(candidates))
    checks['numerical_model']=dict(status='PASS' if numerical.returncode==0 else 'FAIL', command='python -m unittest discover -s stream_video_enhance/tests -p test_reference.py -v',
                                   log='numerical_tests.txt', scope='all constants/modes/epsilon/bounds, variance/division, 288 VGA cases max error<=1, histogram/MAE/RMSE')
    checks['real_image_classes']=dict(status='PASS' if len([c for c in reg['cases'] if c['category']=='real'])>=3 else 'MISSING',
                                      explanation='Public photographs supplement text/texture, and are not OV7670 captures; registered masks are contrast diagnostics without clean truth.')
    checks['real_exposure_classes']=dict(status='MISSING', explanation=reg['evidence_gaps'][0])
    checks['camera_video_evidence']=dict(status='MISSING', explanation=reg['evidence_gaps'][1], required=False)
    checks['future_rtl_bit_exact']=dict(status='DEFERRED', required=False, explanation='Only applicable after model gate PASS; no algorithm RTL exists.')
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
           f"搜索24组共享ε候选，可行候选数：{len(feasible)}。固定选择：`{selected['config']}`，角色：{selected['role']}。",
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
        result['profile_published']=publish_profile(Path(__file__).parent,checks,selected['config'])
        (report_dir/'metrics.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps(dict(status=result['status'],tuning_feasible=len(feasible),selected=selected,failures=list(failures)),ensure_ascii=False))
    return 0 if result['status']=='PASS' else 1


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--register',action='store_true'); group.add_argument('--run',action='store_true')
    parser.add_argument('--report-dir',type=Path,default=ds.DEFAULT_REPORT)
    args=parser.parse_args()
    try:
        if args.register:
            reg=ds.register(args.report_dir)
            print(json.dumps(dict(registered=len(reg['cases']),arrays=len(reg['arrays']),sha256=reg['archive_sha256'])))
            return 0
        return run(args.report_dir)
    except (ValueError,FileNotFoundError,FileExistsError) as exc:
        print(str(exc),file=sys.stderr); return 2


if __name__=='__main__':
    sys.exit(main())
