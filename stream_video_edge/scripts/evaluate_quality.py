"""Registered controlled comparison; runtime thresholds remain manual."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from model.reference import preprocess,gradient

def clean_image():
 a=np.full((96,128),96,np.uint8);a[16:64,80:116]=152
 a[54:86,22:24]=216;a[54:86,42:43]=24
 return a

def dilate(mask):
 p=np.pad(mask,1);return np.logical_or.reduce([p[y:y+mask.shape[0],x:x+mask.shape[1]] for y in range(3) for x in range(3)])

def measures(clean,noisy,filtered,threshold):
 truth=gradient(clean)[4:-4,4:-4]>=160;got=gradient(filtered)>=threshold
 near_truth=dilate(truth);near_got=dilate(got)
 precision=float((got&near_truth).sum()/max(1,got.sum()));recall=float((truth&near_got).sum()/max(1,truth.sum()))
 y,x=np.indices(truth.shape);low=(x+5>=76);thin=(x+5<64)&(y+5>=48)
 recalls=[float((truth&near_got&mask).sum()/max(1,(truth&mask).sum())) for mask in [low,thin]]
 return dict(f1=2*precision*recall/max(1e-20,precision+recall),recall=min(recalls),
  flat_false=float(got[5:25,5:35].mean()),noise_ratio=float(filtered[6:26,6:36].astype(float).std()/noisy[10:30,10:40].astype(float).std()))

def main():
 regpath=ROOT/'model/quality_registration.json';reg=json.loads(regpath.read_text());clean=clean_image()
 samples={s:np.clip(np.rint(clean.astype(float)+np.random.default_rng(s).normal(0,reg['noise_sigma'],clean.shape)),0,255).astype(np.uint8) for s in reg['tuning_seeds']+reg['holdout_seeds']}
 candidates=[]
 filtered={seed:preprocess(samples[seed]) for seed in reg['tuning_seeds']}
 for t in reg['threshold_candidates']:
  m=[measures(clean,samples[seed],filtered[seed],t) for seed in reg['tuning_seeds']]
  stats={k:float(np.mean([a[k] for a in m])) for k in m[0]}
  violations=sum([stats['noise_ratio']>.8,stats['recall']<.9,stats['flat_false']>.01])
  candidates.append(dict(threshold=t,violations=violations,**stats))
 best=min(candidates,key=lambda a:(a['violations'],-a['f1'],a['flat_false'],a['threshold']))
 held=[measures(clean,samples[seed],preprocess(samples[seed]),best['threshold']) for seed in reg['holdout_seeds']]
 passed=all(a['noise_ratio']<=.8 and a['recall']>=.9 and a['flat_false']<=.01 for a in held)
 report=dict(algorithm='GAUSSIAN3',registration_sha256=hashlib.sha256(regpath.read_bytes()).hexdigest(),
  chosen=best,holdout=held,passed=passed,candidates=candidates,scope='controlled only; no camera acceptance claim')
 (ROOT/'reports/quality.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(dict(algorithm='GAUSSIAN3',candidate_threshold=best['threshold'],controlled_gate_pass=passed)))
 return 0 if passed else 1

if __name__=='__main__':raise SystemExit(main())
