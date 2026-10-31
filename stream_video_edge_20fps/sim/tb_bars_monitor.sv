`timescale 1ns/1ps
module tb_bars_monitor;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,enable=1,pv=0;reg[7:0]p;reg[9:0]x;reg[8:0]y;
 reg[7:0]row[0:639];reg[1023:0]folder;
 wire[127:0]status;
 bars_monitor dut(.clk(clk),.rst(rst),.start(start),.enable(enable),.pixel_valid(pv),.pixel(p),.x(x),.y(y),.status(status));
 initial begin
  if(!$value$plusargs("VECTORS=%s",folder))$fatal(1,"vectors");
  $readmemh({folder,"/row.hex"},row);
  repeat(4)@(negedge clk);rst=0;
  for(integer yy=0;yy<4;yy=yy+1)for(integer xx=0;xx<640;xx=xx+1)begin
   x=xx;y=yy;p=row[xx];pv=1;@(negedge clk);
  end
  pv=0;if(status!=0)$fatal(1,"correct bars flagged");
  for(integer yy=0;yy<4;yy=yy+1)for(integer xx=0;xx<640;xx=xx+1)begin
   x=xx;y=yy;p=row[xx]^(((yy==0&&(xx==53||xx==55))||(yy==3&&xx==629))?8'h80:0);pv=1;@(negedge clk);
  end
  pv=0;
  if(status[127:96]!=3||status[95:64]!=53||status[63:32]!=2549||status[31:24]!=(row[53]^8'h80)||status[23:16]!=row[53])$fatal(1,"injected errors not located %h",status);
  start=1;@(negedge clk);start=0;enable=0;pv=1;p=255;repeat(4)@(negedge clk);
  if(status!=0)$fatal(1,"disabled diagnostics flagged");
  $display("PASS tb_bars_monitor known row, injected byte faults and disabled scene");$finish;
 end
endmodule
