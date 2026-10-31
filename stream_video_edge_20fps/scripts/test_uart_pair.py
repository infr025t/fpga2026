from pathlib import Path
import sys,json,zlib,struct
r=Path(__file__).resolve().parents[1];sys.path.insert(0,str(r/'scripts'))
from vivado_tools import run_bench
out=r/'reports'/sys.argv[1];out.mkdir(exist_ok=False)
w,h=(640,480) if '--vga' in sys.argv else (32,24)
sources=[r/'rtl/uart/uart_fast_tx.sv',r/'rtl/debug/uart_pair_stream.sv',r/'sim/tb_uart_pair_stream.sv']
top='tb_uart_pair_stream'
if '--vga' in sys.argv:
 wrapper=out/'vga.sv';wrapper.write_text('module tb_vga_uart_pair;tb_uart_pair_stream #(.W(640),.H(480)) test();endmodule\n');sources.append(wrapper);top='tb_vga_uart_pair'
j=run_bench(sources,top,out,timeout=300,pass_marker='PASS tb_uart_pair_stream',plusargs=['VECTORS='+out.as_posix()])
print(j['reason'])
if not j['passed']:raise SystemExit(1)
data=bytes(int(x,16) for x in (out/'uart.hex').read_text().split());n=2*(w//4)*(h//4);size=n+36
assert len(data)==2*size
for i in range(2):
 packet=data[i*size:(i+1)*size];magic,fid,ww,hh,nn,tick,drop=struct.unpack('<8sIHHIII',packet[:28])
 assert (magic,fid,ww,hh,nn,drop)==(b'YVPAIR1!',i+1,w//4,h//4,n,0)
 assert zlib.crc32(packet[:28])==int.from_bytes(packet[28:32],'little')
 body=packet[32:32+n];assert zlib.crc32(body)==int.from_bytes(packet[32+n:36+n],'little')
 expected=bytes(v for y in range(0,h,4) for x in range(3,w,4) for v in ((x+3*y+i+1)&255,(~(x+3*y+i+1))&255))
 assert body==expected
print('PASS 2 actual UART packets headers, paired order and CRC',w,h)
