`timescale 1ns/1ps
// 显示旁路：保存最新完整ASCII，在视频帧边界一次提交，避免同一行文字前后混用两次结果。
// 仅覆盖左上角144x16像素；小点阵使用组合逻辑，不增加图像RAM，不参与识别计算。
module plate_text_overlay(
 input wire clk,rst,enabled,frame_start,result_event,
 input wire[7:0]result_status,input wire[6:0]result_count,input wire[63:0]result_text,
 input wire[9:0]x,input wire[8:0]y,input wire[7:0]pixel,
 output reg[7:0]out_pixel
);
 reg[63:0]latest_text,active_text;
 reg[3:0]latest_count,active_count;
 reg latest_more,active_more;
 always @(posedge clk)begin
  if(rst)begin
   latest_text<=64'h54494157;active_text<=64'h54494157;
   latest_count<=4;active_count<=4;latest_more<=0;active_more<=0;
  end else begin
   // 退出自主识别时清除旧答案；重新启用后必须等到新的完整结果。
   if(!enabled)begin latest_text<=64'h54494157;latest_count<=4;latest_more<=0;end
   else if(result_event)begin
    latest_more<=0;
    if(result_status!=0)begin latest_text<=64'h525245;latest_count<=3;end
    else if(result_count==0)begin latest_text<=64'h454e4f4e;latest_count<=4;end
    else begin latest_text<=result_text;latest_count<=result_count>8?4'd8:result_count[3:0];latest_more<=result_count>8;end
   end
   if(frame_start)begin
    active_text<=enabled?latest_text:64'h46464f;
    active_count<=enabled?latest_count:4'd3;
    active_more<=enabled&&latest_more;
   end
  end
 end
 // 5x7字库，按从上到下、从左到右排列；屏幕显示放大2倍。
 function automatic[34:0]glyph(input[7:0]c);
  begin case(c)
   "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
   "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
   "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
   "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
   "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
   "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
   "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
   "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
   "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
   "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
   "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
   "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
   "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
   "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
   "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
   "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
   "G":glyph=35'b01111_10000_10000_10111_10001_10001_01111;
   "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
   "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
   "J":glyph=35'b00001_00001_00001_00001_10001_10001_01110;
   "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
   "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
   "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
   "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
   "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
   "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
   "Q":glyph=35'b01110_10001_10001_10001_10101_10010_01101;
   "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
   "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
   "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
   "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
   "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
   "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
   "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
   "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
   "Z":glyph=35'b11111_00001_00010_00100_01000_10000_11111;
   "+":glyph=35'b00100_00100_00100_11111_00100_00100_00100;
   " ":glyph=0;
   default:glyph=35'b01110_10001_00001_00010_00100_00000_00100;
  endcase end
 endfunction
 wire[9:0]dx=x-10'd8;wire[8:0]dy=y-9'd8;
 wire[3:0]slot=dx[7:4];wire[3:0]sx=dx[3:0];
 reg[7:0]ch;reg[34:0]bits;
 integer bit_index;
 always @*begin
  ch=" ";
  if(slot<active_count)ch=active_text[slot[2:0]*8+:8];
  else if(slot==8 && active_more)ch="+";
  bits=glyph(ch);bit_index=34-((dy-1)>>1)*5-((sx-3)>>1);
  out_pixel=pixel;
  if(x>=8 && x<152 && y>=8 && y<24)begin
   out_pixel=0;
   if(sx>=3 && sx<13 && dy>=1 && dy<15)
    out_pixel=bits[bit_index]?8'hff:8'h00;
  end
 end
endmodule
