"""只读取合成数据；实拍评分独立执行，不能影响训练选轮。"""
from pathlib import Path
import argparse,json,math,time,hashlib
import numpy as np
import torch
from torch import nn
from torch.utils.data import TensorDataset,DataLoader
import integer_cnn as q
ROOT=Path(__file__).resolve().parent

class Net(nn.Module):
 def __init__(self):
  super().__init__();self.c1=nn.Conv2d(1,8,3,padding=1);self.c2=nn.Conv2d(8,16,3,padding=1);self.fc=nn.Linear(768,36)
 def forward(self,x,trace=False):
  a1=torch.relu(self.c1(x));p1=torch.nn.functional.max_pool2d(a1,2)
  a2=torch.relu(self.c2(p1));p2=torch.nn.functional.max_pool2d(a2,2);out=self.fc(p2.flatten(1))
  return (out,a1,a2) if trace else out

def accuracy(net,x,y):
 net.eval();correct=0
 with torch.no_grad():
  for i in range(0,len(x),256):correct+=int((net(x[i:i+256]).argmax(1)==y[i:i+256]).sum())
 return correct/len(y)

def quantize(net,calibration):
 # 仅用训练集标定激活范围，权重量化采用二次幂步长，以移位完成重新定标。
 maxima=[0.,0.]
 with torch.no_grad():
  for i in range(0,len(calibration),128):
   _,a1,a2=net(calibration[i:i+128],True);maxima=[max(maxima[0],float(a1.max())),max(maxima[1],float(a2.max()))]
 activation_exp=[math.ceil(math.log2(max(v,1e-9)/255)) for v in maxima]
 m={};details=[];input_exp=-8;shifts=[]
 for idx,(name,layer) in enumerate([('c1',net.c1),('c2',net.c2),('fc',net.fc)]):
  w=layer.weight.detach().numpy();b=layer.bias.detach().numpy();we=math.ceil(math.log2(max(float(np.abs(w).max()),1e-12)/127))
  qw=np.clip(np.rint(w/(2.**we)),-127,127).astype(np.int8);qb=np.rint(b/(2.**(input_exp+we))).astype(np.int32)
  m[name+'w']=qw;m[name+'b']=qb
  bound=int(np.max(np.abs(qb.astype(np.int64))+255*np.abs(qw.astype(np.int64)).reshape(len(qb),-1).sum(1)))
  assert bound<(1<<30),('accumulation overflow risk',bound)
  info=dict(layer=name,input_exponent=input_exp,weight_exponent=we,max_int32_accumulator_bound=bound)
  if idx<2:
   oe=activation_exp[idx];shift=oe-input_exp-we;assert shift>=0 and shift<=24
   shifts.append(shift);info.update(output_exponent=oe,shift=shift);input_exp=oe
  details.append(info)
 m['shifts']=shifts
 return m,dict(layers=details,activation_calibration_maxima=maxima,input_scale='1/256',rounding='nearest positive half up, then ReLU and uint8 saturation')

def main():
 p=argparse.ArgumentParser();p.add_argument('--epochs',type=int,default=24);args=p.parse_args()
 torch.set_num_threads(6);torch.set_num_interop_threads(2);torch.use_deterministic_algorithms(True)
 all_results={}
 for kind in ['gray','edge_norm']:
  torch.manual_seed(604);np.random.seed(604)
  data=np.load(ROOT/'data/train.npz');vd=np.load(ROOT/'data/validation.npz');td=np.load(ROOT/'data/test.npz');pv=np.load(ROOT/'data/plate_validation.npz');pt=np.load(ROOT/'data/plate_test.npz')
  raw=data[kind];x=torch.from_numpy(raw[:,None].astype(np.float32)/256);y=torch.from_numpy(data['labels'])
  vx=torch.from_numpy(vd[kind][:,None].astype(np.float32)/256);vy=torch.from_numpy(vd['labels'])
  pvx=torch.from_numpy(pv[kind][:,None].astype(np.float32)/256);pvy=torch.from_numpy(pv['labels'])
  tx=torch.from_numpy(td[kind][:,None].astype(np.float32)/256);ty=torch.from_numpy(td['labels'])
  loader=DataLoader(TensorDataset(x,y),batch_size=128,shuffle=True,generator=torch.Generator().manual_seed(312),num_workers=0)
  net=Net();opt=torch.optim.AdamW(net.parameters(),lr=.002,weight_decay=.001);sched=torch.optim.lr_scheduler.CosineAnnealingLR(opt,args.epochs,eta_min=.0002)
  dest=ROOT/'models'/kind;dest.mkdir(parents=True,exist_ok=True);best=-1.;best_epoch=0;history=[];start=time.time()
  for epoch in range(1,args.epochs+1):
   net.train();total=correct=0;loss_sum=0.
   for xx,yy in loader:
    opt.zero_grad();logits=net(xx);loss=nn.functional.cross_entropy(logits,yy);loss.backward();opt.step()
    total+=len(yy);correct+=int((logits.argmax(1)==yy).sum());loss_sum+=float(loss.detach())*len(yy)
   sched.step();general_val=accuracy(net,vx,vy);plate_val=accuracy(net,pvx,pvy);val=(general_val+plate_val)/2
   row=dict(epoch=epoch,train_accuracy=correct/total,loss=loss_sum/total,validation_accuracy=val,generic_validation_accuracy=general_val,plate_validation_accuracy=plate_val,elapsed_seconds=round(time.time()-start,2));history.append(row)
   if val>best:best=val;best_epoch=epoch;torch.save(net.state_dict(),dest/'float_weights.pt')
   print(kind,json.dumps(row),flush=True)
  net.load_state_dict(torch.load(dest/'float_weights.pt',weights_only=True));net.eval()
  calibration_indices=np.random.default_rng(182).choice(len(x),2048,replace=False)
  model,quant=quantize(net,x[calibration_indices]);meta=dict(kind=kind,input_shape=[1,32,24],classes='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ',validation_best_epoch=best_epoch,training_selection='mean of generic-font and plate augmented validation only; no real camera evaluation',calibration_seed=182,calibration_samples=2048,quantization=quant)
  q.save(dest,model,meta);loaded=q.load(dest)
  validation_correct=test_correct=0;agreement=0
  for split,arr,label in [('validation',vd[kind],vd['labels']),('test',td[kind],td['labels']),('plate_validation',pv[kind],pv['labels']),('plate_test',pt[kind],pt['labels'])]:
   ips=[];fps=[]
   for i in range(0,len(arr),64):
    ip=q.logits(arr[i:i+64],loaded).argmax(1);ips.extend(ip.tolist())
    with torch.no_grad():fp=net(torch.from_numpy(arr[i:i+64,None].astype(np.float32)/256)).argmax(1).numpy();fps.extend(fp.tolist())
   metric=dict(float_accuracy=float(np.mean(np.array(fps)==label)),integer_accuracy=float(np.mean(np.array(ips)==label)),float_integer_prediction_agreement=float(np.mean(np.array(ips)==fps)),samples=len(label))
   meta[split]=metric
  # 真正逐项循环的参考与矢量化整数结果逐分数相等，而不是只比较argmax。
  for sample in vd[kind][:3]:np.testing.assert_array_equal(q.scalar_logits(sample,loaded),q.logits(sample,loaded)[0])
  meta.update(history=history,budget=q.budget(),model_sha256=hashlib.sha256((dest/'model.bin').read_bytes()).hexdigest(),torch_version=torch.__version__,scalar_reference_samples=3)
  (dest/'training_result.json').write_text(json.dumps(meta,indent=2));all_results[kind]=meta
  print('FROZEN_RESULT',kind,json.dumps({k:meta[k] for k in ['validation','test','plate_validation','plate_test','model_sha256']}),flush=True)
 (ROOT/'training_results.json').write_text(json.dumps(all_results,indent=2))

if __name__=='__main__':main()
