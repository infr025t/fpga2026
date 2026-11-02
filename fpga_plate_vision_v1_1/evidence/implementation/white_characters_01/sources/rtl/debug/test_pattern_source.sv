`timescale 1ns/1ps
// 固定VGA测试图，逐像素坐标及节拍与真实链路相同；用于CRC和流水线核对。
// 已接纳的帧会完整排空，暂停由外部调度器阻止下一次start，不截断正在发送的帧。
module test_pattern_source(input wire clk,rst,start,enable,
 output reg busy=0,valid=0,done=0,output reg[7:0]pixel=0,
 output reg[9:0]x=0,output reg[8:0]y=0);
 reg end_pending=0;
 reg[6:0]cooldown=0;reg[9:0]px=0;reg[8:0]py=0;
 always @(posedge clk)begin
  valid<=0;done<=0;
  if(rst)begin busy<=0;end_pending<=0;cooldown<=0;px<=0;py<=0;x<=0;y<=0;pixel<=0;end
  else if(start)begin busy<=enable;end_pending<=0;cooldown<=0;px<=0;py<=0;end
  else begin
   if(end_pending)begin done<=1;end_pending<=0;end
   if(busy)begin
    if(cooldown!=0)cooldown<=cooldown-1'b1;
    else begin
     cooldown<=11;valid<=1;pixel<=(px+3*py+7)^(px>>3);x<=px;y<=py;
     if(px==639)begin px<=0;if(py==479)begin busy<=0;end_pending<=1;end else py<=py+1'b1;end
     else px<=px+1'b1;
    end
   end
  end
 end
endmodule
