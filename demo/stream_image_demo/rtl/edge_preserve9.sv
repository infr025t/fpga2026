`timescale 1ns/1ps
// Quantized variance-adaptive edge-preserving 3x3 smoothing.
// mean=floor(sum/9), v=9*sum(square)-sum*sum = 81*population variance.
// No data-dependent division. All arithmetic is unsigned until detail extraction.
module edge_preserve9 #(parameter integer EPSILON=64)(
  input wire clk,rst,in_valid,input wire[71:0]window_data,
  input wire[7:0]in_raw,in_fine,input wire[15:0]in_x,in_y,
  output reg out_valid,output reg[7:0]out_raw,out_fine,out_base,
  output reg[15:0]out_x,out_y
);
  reg[11:0]sum_comb;reg[19:0]square_comb;integer i;
  reg[11:0]sum0;reg[19:0]square0;
  reg[7:0]center0,raw0,fine0,mean1,center1,raw1,fine1;
  reg[15:0]x0,y0,x1,y1;reg v0,v1;reg[23:0]variance1;
  wire[23:0]square_sum={4'b0,square0}*24'd9;
  wire[23:0]sum_square={12'b0,sum0}*{12'b0,sum0};
  wire[9:0]half_blend={2'b0,center1}+{2'b0,mean1};
  wire[9:0]edge_blend=({2'b0,center1}*10'd3)+{2'b0,mean1};
  always @*begin
    sum_comb=0;square_comb=0;
    for(i=0;i<9;i=i+1)begin
      sum_comb=sum_comb+window_data[i*8+:8];
      square_comb=square_comb+({12'b0,window_data[i*8+:8]}*{12'b0,window_data[i*8+:8]});
    end
  end
  always @(posedge clk)begin
    if(rst)begin
      v0<=0;v1<=0;out_valid<=0;sum0<=0;square0<=0;variance1<=0;
      center0<=0;raw0<=0;fine0<=0;mean1<=0;center1<=0;raw1<=0;fine1<=0;
      x0<=0;y0<=0;x1<=0;y1<=0;out_x<=0;out_y<=0;out_raw<=0;out_fine<=0;out_base<=0;
    end else begin
      v0<=in_valid;v1<=v0;out_valid<=v1;
      if(in_valid)begin
        sum0<=sum_comb;square0<=square_comb;center0<=window_data[32+:8];
        raw0<=in_raw;fine0<=in_fine;x0<=in_x;y0<=in_y;
      end
      if(v0)begin
        mean1<=sum0/9;variance1<=square_sum-sum_square;
        center1<=center0;raw1<=raw0;fine1<=fine0;x1<=x0;y1<=y0;
      end
      if(v1)begin
        if(variance1<=EPSILON*81)out_base<=mean1;
        else if(variance1<=EPSILON*324)out_base<=half_blend>>1;
        else out_base<=edge_blend>>2;
        out_raw<=raw1;out_fine<=fine1;out_x<=x1;out_y<=y1;
      end
    end
  end
endmodule
