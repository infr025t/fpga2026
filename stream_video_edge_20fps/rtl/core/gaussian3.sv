`timescale 1ns/1ps
module gaussian3 #(parameter W=640,H=480)(
 input wire clk,rst,abort,in_valid,input wire[7:0]in_pixel,input wire[9:0]in_x,
 input wire[8:0]in_y,input wire in_sof,input wire[31:0]in_frame_id,
 output reg out_valid,output reg[7:0]out_pixel,out_raw,output reg[9:0]out_x,
 output reg[8:0]out_y,output reg[31:0]out_frame_id);
 wire rv;wire[23:0]rows;wire[9:0]rx;wire[8:0]ry;wire[31:0]rf;
 row_window3 #(W,H,8) window(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),.in_data(in_pixel),.in_x(in_x),.in_y(in_y),.in_sof(in_sof),.in_frame_id(in_frame_id),.out_valid(rv),.out_rows(rows),.out_x(rx),.out_y(ry),.out_frame_id(rf));
 reg[7:0]l2[0:2],l1[0:2];reg[12:0]sum0;reg v0;
 reg[7:0]raw0;reg[9:0]x0;reg[8:0]y0;reg[31:0]f0;integer k;
 wire[12:0]weighted={5'd0,l2[0]}+{4'd0,l1[0],1'b0}+{5'd0,rows[7:0]}+
 {4'd0,l2[1],1'b0}+{3'd0,l1[1],2'b0}+{4'd0,rows[15:8],1'b0}+
 {5'd0,l2[2]}+{4'd0,l1[2],1'b0}+{5'd0,rows[23:16]};
 always @(posedge clk)begin
  if(rst||abort)begin v0<=0;out_valid<=0;end
  else begin
   v0<=rv&&rx>=2&&ry>=2;out_valid<=v0;
   if(rv)for(k=0;k<3;k=k+1)begin l2[k]<=l1[k];l1[k]<=rows[k*8+:8];end
  end
  sum0<=weighted+13'd8;raw0<=l1[1];x0<=rx-1'b1;y0<=ry-1'b1;f0<=rf;
  out_pixel<=sum0[11:4];out_raw<=raw0;out_x<=x0;out_y<=y0;out_frame_id<=f0;
 end
endmodule
