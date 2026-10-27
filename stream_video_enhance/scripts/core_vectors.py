"""Task 3 vectors: unchanged fixed model plus independently calculated literals."""
import importlib.util
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('core_reference', ROOT/'model/reference.py')
ref = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ref)


def generate_stage_vectors(path):
    rng = np.random.default_rng(20261026)
    coefficients = []
    for eps in ref.EPSILONS:
        for value in (0, 1, 127, 128, 254, 255):
            coefficients.append((25*value,25*value*value,eps,value,0,256*value,0))
        # Twelve black and thirteen white samples attain the exact V maximum.
        for samples in [np.array([0]*12+[255]*13), *rng.integers(0,256,(250,25))]:
            s1,s2 = int(samples.sum()), int((samples*samples).sum())
            v = 25*s2-s1*s1
            a = int(ref.ratio_q12(v,eps)); m = (256*s1+12)//25
            coefficients.append((s1,s2,eps,int(samples[12]),a,((4096-a)*m+2048)//4096,0))
    coefficients += [(1,0,16,8,0,0,1),(6376,1625625,16,8,0,0,1),
                     (0,1625626,1024,8,0,0,1),(0,0,17,8,0,0,1)]
    # Literal reconstructed Q8 half tie, no premature U8 rounding, joint maxima clamp.
    rec = [(0,0,0,0),(0,65280,255,65280),(8,0,1,1),(7,0,1,0),
           (4092,65280,255,65280),(2048,128,1,256)]
    for a,b,i in zip(rng.integers(0,4093,1000),rng.integers(0,65281,1000),rng.integers(0,256,1000)):
        rec.append((int(a),int(b),int(i),min(((int(a)*int(i)+8)>>4)+int(b),65280)))
    # raw, Bq8, T, G, mode, expected selected. Half ties +/-128 with gain128
    # deliberately straddle a final pixel half boundary, so ties-away is observable.
    enh = [(101,25727,0,128,3,101),(100,25729,0,128,3,100),
           (100,25855,0,128,3,100),
           (120,25600,4,512,3,132),(80,25600,4,512,3,68),
           (255,65024,0,512,3,255),(0,256,0,512,3,0),
           (108,25600,4,320,3,105),(112,25600,4,320,3,110),
           (116,25600,4,320,3,115),(120,25600,4,320,3,120),
           (112,25600,4,428,3,113),(112,25600,2,256,2,110)]
    for raw,base,t,g,mode,out in enh:
        got=int(ref.enhance_fixed(np.array([[raw]],np.uint8),np.array([[base]],np.int64),t,g)[0,0])
        assert got==out,(raw,base,t,g,got,out)
    for t in (0,2,4,16):
        for g in (0,1,128,256,320,428,512):
            for d in (0,1,127,128,129,t*256-1,t*256,t*256+1,(t+16)*256-1,(t+16)*256,(t+16)*256+1):
                for sign in (-1,1):
                    base=32768-sign*d
                    if not 0<=base<=65280: continue
                    for mode in range(4):
                        gg=256 if mode==2 else g
                        out=128 if mode==0 else ((base+128)>>8) if mode==1 else int(ref.enhance_fixed(np.array([[128]],np.uint8),np.array([[base]],np.int64),t,gg)[0,0])
                        enh.append((128,base,t,g,mode,out))
    count=max(len(coefficients),len(rec),len(enh))
    with (path/'stages.txt').open('w') as f:
        for i in range(count):
            f.write(' '.join(map(str,(*coefficients[i%len(coefficients)],*rec[i%len(rec)],*enh[i%len(enh)])))+'\n')
    return dict(rows=count,coefficient_fixtures=len(coefficients),reconstruction_fixtures=len(rec),enhancement_fixtures=len(enh))

def generate_core_vectors(path, width, height, quick=False):
    """Frames use the frozen model. Scheduling/latency is exclusively in the SV bench."""
    rng=np.random.default_rng(2026102600+width)
    yy,xx=np.indices((height,width))
    if width==640:
        configs=[(16,0,0,0,0),(64,16,512,1,0),(256,2,256,2,0),(1024,4,428,3,0),
                 (16,0,512,3,0),(64,16,0,3,0),(256,0,256,2,0),(1024,4,320,3,0),
                 (1024,4,428,0,0),(1024,4,428,1,0),(1024,2,256,2,0),(1024,4,428,3,0)]
    else:
        configs=[(e,t,g,m,s) for e in ref.EPSILONS for t in (0,16) for g in (0,256,512) for m in range(4) for s in (0,1)]
        configs += [(1024,2,256,2,1),(1024,4,428,3,1),(64,4,320,3,0),(256,4,320,3,1)]
    if quick:configs=configs[:2]
    with (path/'frames.txt').open('w') as listing:
        for idx,(eps,t,g,mode,schedule) in enumerate(configs):
            kind=idx%12
            if kind<4:image=ref.pattern(width,height,idx+1,kind)
            elif kind==4:image=((xx*17+yy*31+xx*yy)%256).astype(np.uint8)
            elif kind==5:image=rng.integers(0,256,(height,width),dtype=np.uint8)
            elif kind==6:image=np.zeros((height,width),np.uint8);image[height//2,width//2]=255
            elif kind==7:image=((yy*13)%256+np.zeros_like(xx)).astype(np.uint8)
            elif kind==8:image=np.full((height,width),255,np.uint8)
            elif kind==9:image=np.zeros((height,width),np.uint8)
            elif kind==10:image=np.where((xx+yy)%2,255,0).astype(np.uint8)
            else:image=np.clip(128+32*np.where((2*xx+yy+3)%8<4,1,-1)+rng.integers(-8,9,(height,width)),0,255).astype(np.uint8)
            layers=ref.fixed_layers(image,eps)
            raw=layers['raw'].astype(np.uint32);base=((layers['base_q8']+128)>>8).astype(np.uint32)
            selected=ref.filter_fixed(image,eps,t,256 if mode==2 else g,ref.MODES[mode]).astype(np.uint32)
            packed=(raw<<16)|(base<<8)|selected
            np.savetxt(path/f'image_{idx}.hex',image.ravel(),fmt='%02x')
            np.savetxt(path/f'expected_{idx}.hex',packed.ravel(),fmt='%06x')
            listing.write(f'{idx} {eps} {t} {g} {mode} {schedule}\n')
    return dict(width=width,height=height,frames=len(configs),pixels_per_frame=(width-8)*(height-8),seed=2026102600+width)


CORE_SOURCES=('core_latency_pkg.sv','token_pipe.sv','div25_pipe.sv','ratio_q12_pipe.sv',
              'row_window5.sv','moments5.sv','coefficient_box5.sv','coefficient5.sv',
              'reconstruct.sv','detail_enhance.sv','guided_core.sv')


def run_core_suite(args):
    import json,uuid
    from run_core_tests import run_bench as base_run_bench
    def run_bench(*positional, **keywords):
        # Task 3 additionally rejects warnings; keep the existing primitive runner API intact.
        import re
        result=base_run_bench(*positional, **keywords)
        warnings=[]
        for stage in result['stages']:
            warnings.extend(line for line in Path(stage['log']).read_text(errors='replace').splitlines()
                            if re.match(r'\s*WARNING:',line,re.I))
        result['warnings']=warnings
        if warnings:
            result['passed']=False;result['reason']='warning diagnostics'
        (Path(result['work_dir'])/'result.json').write_text(json.dumps(result,indent=2))
        return result
    results=[]
    if args.core_size in ('all','stages'):
        p=ROOT/'build/regression'/('core-stages-'+uuid.uuid4().hex[:10]);p.mkdir(parents=True)
        counts=generate_stage_vectors(p)
        result=run_bench([*(ROOT/'rtl'/s for s in CORE_SOURCES),ROOT/'sim/tb_core_stages.sv'],
                         'tb_core_stages',p,timeout=args.timeout,plusargs=['VECTORS='+p.as_posix()])
        result['vectors']=counts;(p/'result.json').write_text(json.dumps(result,indent=2));results.append(result)
    for name,w,h in [('16',16,16),('17',17,19),('vga',640,480)]:
        if args.core_size not in ('all',name):continue
        for align in (0,1):
            if args.extra_align not in ('both',str(align)):continue
            p=ROOT/'build/regression'/('core-'+name+'-align'+str(align)+'-'+uuid.uuid4().hex[:10]);p.mkdir(parents=True)
            counts=generate_core_vectors(p,w,h,args.quick)
            result=run_bench([*(ROOT/'rtl'/s for s in CORE_SOURCES),ROOT/'sim/tb_guided_core.sv'],
                             'tb_guided_core_'+name+('_align' if align else ''),p,timeout=args.timeout,
                             pass_marker='PASS tb_guided_core',plusargs=['VECTORS='+p.as_posix()])
            result['vectors']=counts;(p/'result.json').write_text(json.dumps(result,indent=2));results.append(result)
    if args.core_size in ('all','faults'):
        for align in (0,1):
            if args.extra_align not in ('both',str(align)):continue
            p=ROOT/'build/regression'/('core-faults-align'+str(align)+'-'+uuid.uuid4().hex[:10])
            result=run_bench([*(ROOT/'rtl'/s for s in CORE_SOURCES),ROOT/'sim/tb_guided_core.sv'],
                             'tb_core_faults_'+str(align),p,timeout=args.timeout,pass_marker='PASS tb_core_faults')
            results.append(result)
    print(json.dumps(results,indent=2))
    return 0 if results and all(r['passed'] for r in results) else 1
