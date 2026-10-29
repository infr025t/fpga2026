"""Receive EVG2 photographs. UART reception never repairs/filter pixels."""
import argparse,concurrent.futures,json,os,queue,struct,sys,threading,time,traceback,zlib
from pathlib import Path
from protocol import HEADER,decode,canvas,FILTERS,VIEWS
ROOT=Path(__file__).resolve().parents[1]

def atomic_bytes(path,value):
 path=Path(path);temp=path.with_name(path.name+'.tmp');temp.write_bytes(value);temp.replace(path)

def atomic_json(path,value):atomic_bytes(path,(json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode('utf-8'))

def read_packet(port,buffer,check,timeout=60):
 deadline=time.monotonic()+timeout;target=None
 while time.monotonic()<deadline:
  check();chunk=port.read(8192)
  if chunk:buffer.extend(chunk)
  if target is None:
   at=buffer.find(b'EVG2')
   if at<0:
    if len(buffer)>3:del buffer[:-3]
    continue
   if at:del buffer[:at]
   if len(buffer)<32:continue
   h=HEADER.unpack_from(buffer)
   if h[:2]!=(b'EVG2',2) or h[4:7]!=(32,630,470) or h[8]!=630*470 or zlib.crc32(buffer[:28])!=h[-1]:raise ValueError('Unexpected EVG2 VGA header')
   target=32+h[8]+20
  if len(buffer)>=target:
   result=bytes(buffer[:target]);del buffer[:target];return result
 raise TimeoutError(f'EVG2 frame incomplete: buffered{len(buffer)} bytes')

def reference_pixels(frame):
 sys.path.insert(0,str(ROOT));from model.reference import process,pattern
 a=pattern(frame_id=7);raw,edge=process(a,frame.filter_id,frame.epsilon,frame.threshold)
 return (edge if frame.view else raw).tobytes(),zlib.crc32(a.tobytes())

def save_frame(folder,number,wire,source,verify_reference):
 from PIL import Image
 frame=decode(wire)
 if verify_reference:
  expected,source_crc=reference_pixels(frame)
  if expected!=frame.pixels or source_crc!=frame.source_crc:raise ValueError('Hardware input/output differs from deterministic reference')
 folder=Path(folder)/FILTERS[frame.filter_id]/VIEWS[frame.view];folder.mkdir(parents=True,exist_ok=True)
 stem=f'frame_{number:03d}_id{frame.frame_id:08d}';path=folder/(stem+'.png')
 if path.exists():raise FileExistsError(str(path))
 im=Image.frombytes('L',(frame.width,frame.height),frame.pixels)
 temp=path.with_suffix('.png.tmp');im.save(temp,format='PNG');temp.replace(path)
 canvas_path=path.with_name(stem+'_canvas.png');Image.frombytes('L',(640,480),canvas(frame)).save(canvas_path)
 atomic_bytes(path.with_suffix('.bin'),frame.pixels);atomic_bytes(path.with_suffix('.wire'),wire)
 metadata=dict(number=number,frame_id=frame.frame_id,filter=FILTERS[frame.filter_id],view=VIEWS[frame.view],
  width=frame.width,height=frame.height,epsilon=frame.epsilon,threshold=frame.threshold,
  payload_crc32=f'{frame.payload_crc:08x}',source_crc32=f'{frame.source_crc:08x}',source=source,
  bit_exact_reference_verified=verify_reference,real_camera_image_quality_verified=False,image=str(path))
 atomic_json(path.with_suffix('.json'),metadata);return path,metadata

class Window:
 def __init__(self,args):
  import tkinter as tk
  from PIL import ImageTk
  self.args=args;self.ImageTk=ImageTk;self.root=tk.Tk();self.root.title('FPGA v0.3 RAW / EDGE')
  self.root.resizable(False,False);self.label=tk.Label(self.root,text='连接COM10，等待单帧…');self.label.pack()
  self.picture=tk.Label(self.root,width=640,height=480);self.picture.pack();self.photo=None
  self.folder=args.output;self.folder.mkdir(parents=True,exist_ok=False)
  self.events=queue.Queue();self.cancel=threading.Event();self.finished=False;self.state=dict(status='CONNECTING',saved=0,displayed=0,target=args.frames,
   source=args.source,port='COM10',baud=12000000,pid=os.getpid(),output=str(self.folder))
  self.lock=threading.RLock();self.update();self.root.protocol('WM_DELETE_WINDOW',self.close)
  threading.Thread(target=self.worker,daemon=True).start();self.root.after(40,self.poll)
 def update(self,**kw):
  with self.lock:self.state.update(kw);atomic_json(self.folder/'progress.json',self.state)
 def check(self,job=None):
  if self.cancel.is_set():raise InterruptedError('Window closed')
  if job is not None and job.done() and job.result()!=(0,False):raise RuntimeError('JTAG controller failed; see control_stdout.log')
 def worker(self):
  try:
   import serial
   sys.path.insert(0,str(ROOT/'scripts'));from vivado_tools import _run_tool
   total=self.state['target'];last_id=0;buffer=bytearray()
   with serial.Serial('COM10',12000000,timeout=.1) as port,concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
    port.reset_input_buffer();job=None
    log=(self.folder/'control_stdout.log').open('w',encoding='utf-8')
    try:
     if self.args.auto:
      cmd=['E:/Vivado/2025.1/Vivado/bin/vivado.bat','-mode','batch','-source',str(ROOT/'scripts/capture_control.tcl'),
       '-log',str(self.folder/'control.log'),'-journal',str(self.folder/'control.jou'),'-tclargs',str(self.folder),str(total),
       '1' if self.args.source=='internal' else '0',str(self.args.threshold or 0)]
      job=pool.submit(_run_tool,cmd,self.folder,log,600)
     self.update(status='CAPTURING')
     for number in range(1,total+1):
      wire=read_packet(port,buffer,lambda:self.check(job));frame=decode(wire)
      if self.args.auto and (frame.filter_id*2+frame.view!=(number-1)%4 or frame.frame_id!=number):raise ValueError('Unexpected filter/view order or frame ID')
      last_id=frame.frame_id
      try:
       path,meta=save_frame(self.folder,number,wire,self.args.source.upper(),self.args.source=='internal')
      except Exception:
       atomic_bytes(self.folder/f'rejected_{number:04d}.wire',wire)
       atomic_bytes(self.folder/'abort.flag',b'stop')
       raise
      atomic_bytes(self.folder/'latest.png',path.read_bytes());atomic_json(self.folder/'latest.json',meta)
      self.update(saved=number,last_image=str(path));self.events.put(('frame',number,path,meta))
     if job is not None:
      result=job.result(timeout=60)
      if result!=(0,False):raise RuntimeError('JTAG completion failed')
    finally:log.close()
   self.events.put(('done',))
  except Exception as error:
   atomic_bytes(self.folder/'abort.flag',b'stop')
   if 'buffer' in locals() and buffer:atomic_bytes(self.folder/'partial.wire',bytes(buffer))
   atomic_json(self.folder/'error.json',dict(error=str(error),traceback=traceback.format_exc()))
   self.events.put(('error',str(error)))
 def poll(self):
  try:
   while True:
    event=self.events.get_nowait()
    if event[0]=='frame':
     from PIL import Image
     _,number,path,meta=event
     with Image.open(path) as im:self.photo=self.ImageTk.PhotoImage(im)
     self.picture.configure(image=self.photo,width=630,height=470)
     self.label.configure(text=f"{meta['filter']} / {meta['view']}  T={meta['threshold']}  {number}/{self.state['target']} 已保存")
     self.root.update_idletasks();self.update(displayed=number)
     if self.args.auto:atomic_bytes(self.folder/f'capture_{number:04d}.ack',b'OK')
    elif event[0]=='done':self.finished=True;self.update(status='COMPLETE');self.root.title('FPGA v0.3 | COMPLETE')
    elif event[0]=='error':self.finished=True;self.update(status='FAILED',error=event[1]);self.label.configure(text=event[1])
  except queue.Empty:pass
  except Exception as error:self.update(status='FAILED',error=str(error));self.cancel.set();atomic_bytes(self.folder/'abort.flag',b'stop')
  self.root.after(40,self.poll)
 def close(self):
  if not self.finished:self.cancel.set();atomic_bytes(self.folder/'abort.flag',b'stop');self.update(status='CANCELLED')
  self.root.destroy()

def parse_args(argv=None):
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--auto',action='store_true',help='JTAG switches/trigger control; four filter/view combinations per round')
 ap.add_argument('--source',choices=['camera','internal'],default='camera')
 count=ap.add_mutually_exclusive_group()
 count.add_argument('--rounds',type=int,help='Number of four-configuration rounds,1..25')
 count.add_argument('--frames',type=int,help='Exact automatic capture count,1..100 (including50)')
 ap.add_argument('--threshold',type=int,help='Manual Sobel threshold: multiple of4 in4..2040; omit to use per-filter defaults')
 ap.add_argument('--output',type=Path,default=Path('E:/FPGA_Test_Work/edge_v03_work')/f'capture_{time.time_ns()}')
 args=ap.parse_args(argv)
 if not args.auto and (args.frames is not None or args.rounds is not None):ap.error('frames/rounds require --auto')
 if args.rounds is not None and not 1<=args.rounds<=25:ap.error('rounds must be1..25')
 if args.frames is not None and not 1<=args.frames<=100:ap.error('frames must be1..100')
 args.frames=(args.frames if args.frames is not None else 4*(args.rounds or 1)) if args.auto else 1
 if args.threshold is not None and (not 4<=args.threshold<=2040 or args.threshold%4):ap.error('threshold must be multiple of4 in4..2040')
 return args

def main():
 app=Window(parse_args());app.root.mainloop()

if __name__=='__main__':main()
