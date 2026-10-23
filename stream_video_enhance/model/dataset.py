"""Pre-search registration. Archived arrays, not RNG/library drift, define inputs."""
from pathlib import Path
import hashlib
import json
import platform
import shutil
import subprocess
import numpy as np
from PIL import Image, ImageDraw, __version__ as pillow_version

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REPORT = ROOT / 'stream_video_enhance/reports/model_gate'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def gray_round(values):
    # All values represent nonnegative gray levels; negatives saturate to zero.
    return np.clip(np.floor(np.asarray(values) + .5), 0, 255).astype(np.uint8)


def _required_checks(primary):
    return ['flat_sigma8_psnr','flat_mean_bias','clean_line_retention','clean_step_far',
            'default_step_overshoot','enhance_step_overshoot',
            *['primary_'+k for k in primary['holdout']],
            'flat_noise_sigma2','flat_noise_sigma4','flat_noise_sigma8','new_clipping',
            'repeated64_exact','temporal64_noise','tuning_feasible','numerical_model','real_image_classes']


def _patterns(split, experiment='original-v1'):
    h, w = 96, 128
    y, x = np.indices((h, w))
    offset = 0 if split == 'tuning' else 3
    patterns = {}
    def add(name, image, fg=None, bg=None, category=None):
        if fg is None:
            fg = image > np.median(image)
            bg = image <= np.median(image)
            if not fg.any():
                fg, bg = x < w//2, x >= w//2
        patterns[name] = (image.astype(np.uint8), fg.astype(bool), bg.astype(bool), category or name)
    add('flat', np.full((h, w), 128 + offset), category='flat')
    for axis in ('vertical', 'horizontal'):
        q = x if axis == 'vertical' else y
        for width in (1, 2, 4):
            fg = ((q-offset) % 16) < width
            bg = (((q-offset) % 16) >= width+2) & (((q-offset) % 16) <= 13)
            add(f'line_{axis}_{width}', np.where(fg, 192, 64), fg, bg, 'line')
    for amplitude in (16, 32):
        for period in (4, 8):
            # Distinct holdout geometry: checker textures, versus tuning stripes.
            fg = ((x+offset)//(period//2) + (y//(period//2) if split == 'holdout' else 0)) % 2 == 0
            if experiment == 'expanded-v2' and split == 'holdout':
                # New geometry: diagonal alternating bands, never round1's
                # vertical stripes or checkerboard translated to a new phase.
                fg = (x+2*y+1) % period < period//2
            add(f'texture_p{period}_a{amplitude}', np.where(fg, 128+amplitude, 128-amplitude), fg, ~fg, 'texture')
    canvas = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(canvas)
    text = 'FPGA 123\nSobel 5x5\nRaw + Detail' if split == 'tuning' else 'Video 64\nEdges II=1\nNoise sigma8'
    position = (12+offset, 16+offset)
    if experiment == 'expanded-v2' and split == 'holdout':
        text, position = 'Core VGA\nGain 512\nPixel 2026', (7, 11)
    draw.multiline_text(position, text, fill=255, spacing=7)
    fg = np.asarray(canvas) > 127
    # Adjacent background: 5x5 dilation, excluding actual strokes.
    dilated = np.asarray(canvas.filter(__import__('PIL.ImageFilter', fromlist=['MaxFilter']).MaxFilter(5))) > 0
    add('text_low', np.where(fg, 144, 112), fg, dilated & ~fg, 'text')
    for direction, distance in [('vertical', x-w//2-offset), ('horizontal', y-h//2-offset),
                                 ('diagonal', (x-y-w//4-offset)/np.sqrt(2))]:
        add('step_'+direction, np.where(distance >= 0, 224, 32), distance >= 8, distance <= -8, 'step')
    add('gradient', gray_round((x+y)/(h+w-2)*255), category='gradient')
    add('checker', np.where((x+y+offset)%2, 255, 0), category='checker')
    impulse = np.zeros((h, w), np.uint8); impulse[h//2+offset, w//2] = 255
    add('impulse', impulse, category='impulse')
    add('highlights', np.where(x < 30+offset, 0, np.where(x > 95+offset, 255, 128)), category='highlights')
    return patterns


def register(report_dir=DEFAULT_REPORT, include_sources=True, experiment='original-v1'):
    if experiment not in ('original-v1', 'expanded-v2'):
        raise ValueError('Unknown registered experiment: '+experiment)
    expanded = experiment == 'expanded-v2'
    report_dir = Path(report_dir)
    if (report_dir/'registration.json').exists() or (report_dir/'inputs.npz').exists():
        raise FileExistsError('Registration is immutable; use a new experiment directory')
    report_dir.mkdir(parents=True, exist_ok=True)
    arrays, cases, sequences = {}, [], []
    primary = {s: [s+'_text_low_clean', s+'_texture_p4_a32_clean'] for s in ('tuning', 'holdout')}
    for split in ('tuning', 'holdout'):
        patterns = _patterns(split, experiment)
        for pattern_index, (name, (clean, fg, bg, category)) in enumerate(patterns.items()):
            prefix = split+'_'+name
            arrays[prefix+'_clean'] = clean
            arrays[prefix+'_fg'] = fg
            arrays[prefix+'_bg'] = bg
            for sigma in (0, 2, 4, 8, 16):
                for seed in (range(5) if sigma else [None]):
                    key = prefix+'_clean' if sigma == 0 else prefix+f'_s{sigma}_n{seed}'
                    # Same enumerated seed IDs, disjoint split seed streams.
                    if sigma:
                        entropy = [2026102302, int(split=='holdout'), pattern_index, sigma, seed] if expanded else [20261023, int(split=='holdout'), sigma, seed]
                        rng = np.random.Generator(np.random.PCG64(np.random.SeedSequence(entropy)))
                        arrays[key] = gray_round(clean.astype(float)+rng.normal(0, sigma, clean.shape))
                    cases.append(dict(id=key, split=split, category=category, clean=prefix+'_clean',
                                      foreground=prefix+'_fg', background=prefix+'_bg', sigma=sigma, seed=seed,
                                      provenance='synthetic', dimensions=list(clean.shape)))
        flat = patterns['flat'][0]
        rng = np.random.Generator(np.random.PCG64(np.random.SeedSequence([2026102302 if expanded else 20261023, int(split=='holdout'), 64])))
        arrays[split+'_repeated'] = np.repeat(patterns['text_low'][0][None], 64, axis=0)
        arrays[split+'_temporal_noise'] = gray_round(flat.astype(float)[None]+rng.normal(0, 8, (64, *flat.shape)))
        yy, xx = np.indices(flat.shape)
        arrays[split+'_moving'] = np.stack([np.where(xx < 30+i+(3 if split=='holdout' else 0), 32, 224) for i in range(64)]).astype(np.uint8)
        arrays[split+'_exposure_simulated'] = np.stack([gray_round(patterns['text_low'][0].astype(float)+(i-32)/2) for i in range(64)])
        for kind in ('repeated', 'temporal_noise', 'moving', 'exposure_simulated'):
            sequences.append(dict(id=split+'_'+kind, split=split, kind=kind, frames=64, provenance='synthetic'))
    sources = []
    if include_sources:
        if expanded:
            (report_dir/'sources').mkdir(exist_ok=True)
            for filename in ('camera.png', 'text.png', 'provenance.json'):
                shutil.copyfile(DEFAULT_REPORT/'sources'/filename, report_dir/'sources'/filename)
        # Only explicitly documented real camera evidence. No mode1 Sobel or
        # synthetic regression PGM is admitted as RAW camera input.
        source_specs = [
            (ROOT/'demo/stream_image_demo/evidence/focus_latest.png', (0,22,318,260), 'ov7670_graphite', 'actual_camera',
             'docs/开发与联调日志.txt lines63/197: contact sheet frames464/581; first RAW panel, graphite cross'),
            (report_dir/'sources/text.png', None, 'public_text', 'public_real_photo', 'scikit-image v0.25.2 text.png; public domain Corner.png'),
            (report_dir/'sources/camera.png', (0,16,512,496), 'public_camera', 'public_real_photo', 'scikit-image v0.25.2 camera.png; CC0 Lav Varshney'),
        ]
        for path, crop, name, kind, evidence in source_specs:
            if not path.exists():
                sources.append(dict(id=name, path=str(path), status='MISSING', evidence=evidence)); continue
            sourcebytes = path.read_bytes()
            image = Image.open(path).convert('L')
            if crop:
                image = image.crop(crop)
            image = np.asarray(image).copy()
            # Full source crops retained, no resampling. Fixed photographic
            # masks encode high/low quantiles; they are not clean references.
            yy, xx = np.indices(image.shape)
            fg = image >= np.quantile(image, .7); bg = image <= np.quantile(image, .3)
            for suffix, arr in [('clean', image), ('fg', fg), ('bg', bg)]:
                arrays[name+'_'+suffix] = arr
            sources.append(dict(id=name, path=str(path), file_sha256=sha(sourcebytes), crop=crop,
                                kind=kind, evidence=evidence, status='PRESENT', dimensions=list(image.shape)))
            cases.append(dict(id=name+'_clean', split='holdout', category='real', clean=None, sigma=None,
                              seed=None, foreground=name+'_fg', background=name+'_bg', provenance=kind,
                              dimensions=list(image.shape)))
        if expanded:
            # Coordinates are in the registered crop. camera.png original sky
            # (0,0,130,65) -> (0,0,130,49) after crop y0=16; grass original
            # (350,300,500,480) -> (350,284,500,464). Every mask is frozen here
            # before search and hashed with the input archive, never inferred
            # from processed outputs or a supposed clean photographic truth.
            regions = [('public_camera', 'flat', (0,0,130,49)),
                       ('public_camera', 'texture', (350,284,500,464)),
                       ('public_text', 'text', None),
                       ('ov7670_graphite', 'text', None)]
            cases[:] = [c for c in cases if c['category'] != 'real']
            for name, region_class, box in regions:
                if name+'_clean' not in arrays:
                    continue
                image = arrays[name+'_clean']
                h,w = image.shape
                box = box or (4,4,w-4,h-4)
                x0,y0,x1,y1 = box
                yy,xx = np.indices(image.shape)
                mask = (xx>=x0)&(xx<x1)&(yy>=y0)&(yy<y1)
                if region_class == 'flat':
                    fg, bg = mask&(xx<(x0+x1)//2), mask&(xx>=(x0+x1)//2)
                else:
                    fg = mask & (image >= np.quantile(image[mask], .7))
                    bg = mask & (image <= np.quantile(image[mask], .3))
                key = name+'_'+region_class+'_region'
                for suffix, value in [('',image),('_mask',mask),('_fg',fg),('_bg',bg)]:
                    arrays[key+suffix] = value
                source = next(s for s in sources if s['id']==name)
                cases.append(dict(id=key, split='holdout', category='real', region_class=region_class,
                                  source_id=name, region_box=list(box), region_mask=key+'_mask',
                                  clean=None, sigma=None, seed=None, foreground=key+'_fg', background=key+'_bg',
                                  provenance=source['kind'], dimensions=list(image.shape)))
    archive = report_dir/'inputs.npz'
    np.savez_compressed(archive, **arrays)
    manifest = dict(schema=1, registration_date='2026-10-23', generator='NumPy PCG64 SeedSequence; normal, floor(gray+0.5), clip0..255 U8',
                    versions=dict(python=platform.python_version(), numpy=np.__version__, pillow=pillow_version),
                    split_seed_entropy='[20261023, split(0=tuning,1=holdout), sigma, seed0..4]; temporal=[20261023,split,64]',
                    crop='all metric arrays and masks [4:-4,4:-4]', archive='inputs.npz', archive_sha256=sha(archive.read_bytes()),
                    arrays={key:dict(sha256=sha(value.tobytes(order='C')), shape=list(value.shape), dtype=str(value.dtype)) for key,value in arrays.items()},
                    cases=cases, sequences=sequences, primary_enhancement=primary, sources=sources,
                    candidates=dict(epsilon=[64,256], denoise_threshold=[2,4,8], enhance_threshold=[2,4], enhance_gain=[384,448], limit=16),
                    tuning_selection='First feasible candidate ordered epsilon,T_D,T_E,G_E ascending; if none, first candidate is diagnostic only. Never rank holdout.',
                    evidence_gaps=['Different-exposure actual photographs/captures with recorded exposure are unavailable.',
                                   'Locked-exposure actual-camera 64-frame RAW sequence unavailable; synthetic sequence is simulated.',
                                   'Actual OV7670 fine text and independent natural texture scenes unavailable; public real photos supplement real-image classes only.'])
    if expanded:
        manifest.update(schema=2, experiment=experiment,
                        source_model_commit=subprocess.run(['git','rev-parse','HEAD'], cwd=ROOT, capture_output=True,text=True,check=True).stdout.strip(),
                        split_seed_entropy='PCG64 SeedSequence [2026102302, split(0=tuning,1=holdout), pattern_index, sigma, seed0..4]; temporal=[2026102302,split,64]',
                        candidates=dict(epsilon=[16,64,256,1024], denoise_threshold=[2,4,8], enhance_threshold=[2,4], enhance_gain=[384,448,512], limit=16),
                        fixture_policy=dict(canonical_stress='REUSED_NOT_NOVEL_HOLDOUT_EVIDENCE',
                                            reused_categories=['flat','line','step','gradient','checker','impulse','highlights','moving'],
                                            novel_holdout='New text Core VGA/Gain 512/Pixel 2026 at (7,11); diagonal bands (x+2*y+1)%period < period/2, period4/8 amplitude16/32.',
                                            tuning='Round1 clean pattern definitions retained; all noise and temporal noise streams replaced.'),
                        evidence_policy=dict(real_exposure_classes=dict(status='DEFERRED', required=False, milestone='camera_integration', authorization='User 2026-10-23 explicitly deferred actual exposure quality; never PASS from synthetic data.'),
                                             camera_video_evidence=dict(status='DEFERRED', required=False, milestone='camera_integration'),
                                             future_rtl_bit_exact=dict(status='DEFERRED', required=False, milestone='algorithm_RTL')))
        manifest['required_checks'] = _required_checks(primary)
    (report_dir/'registration.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return manifest


def load_registration(report_dir=DEFAULT_REPORT):
    report_dir = Path(report_dir)
    registration = json.loads((report_dir/'registration.json').read_text(encoding='utf-8'))
    if registration.get('experiment') == 'expanded-v2':
        # This known experiment has two frozen targets in each split. Do not
        # derive the binding contract from editable registration metadata: an
        # omitted primary and an equally shortened inventory must still fail.
        frozen_primary = {split:[split+'_text_low_clean',split+'_texture_p4_a32_clean']
                          for split in ('tuning','holdout')}
        if registration.get('primary_enhancement') != frozen_primary:
            raise ValueError('Expanded primary targets must exactly match the frozen two-class contract')
        for split, targets in frozen_primary.items():
            for key, category in zip(targets, ('text','texture')):
                cases = [c for c in registration['cases'] if c.get('id')==key]
                if len(cases)!=1 or any(cases[0].get(k)!=v for k,v in
                        dict(split=split,category=category,clean=key,sigma=0,seed=None,
                             foreground=key.removesuffix('_clean')+'_fg',
                             background=key.removesuffix('_clean')+'_bg').items()):
                    raise ValueError('Expanded primary case does not match its frozen split/class/clean target: '+key)
        expected = _required_checks(frozen_primary)
        required = registration.get('required_checks', [])
        if set(required) != set(expected) or len(required) != len(expected):
            raise ValueError('Expanded required check inventory is incomplete or unknown')
        policy = registration.get('evidence_policy', {})
        expected_policy = {'real_exposure_classes','camera_video_evidence','future_rtl_bit_exact'}
        if set(policy) != expected_policy or any(p.get('required') is not False or p.get('status')!='DEFERRED' for p in policy.values()):
            raise ValueError('Expanded evidence policy must preserve required controlled checks and DEFERRED camera/RTL evidence')
    archive = report_dir/registration['archive']
    if sha(archive.read_bytes()) != registration['archive_sha256']:
        raise ValueError('Registered archive hash mismatch')
    with np.load(archive, allow_pickle=False) as z:
        arrays = {key: z[key] for key in z.files}
    if set(arrays) != set(registration['arrays']):
        raise ValueError('Registered array inventory mismatch')
    for key, value in arrays.items():
        entry = registration['arrays'][key]
        if list(value.shape) != entry['shape'] or str(value.dtype) != entry['dtype'] or sha(value.tobytes(order='C')) != entry['sha256']:
            raise ValueError('Registered input bytes differ: '+key)
    return registration, arrays
