`timescale 1ns/1ps
module sobel3 #(parameter W=632,H=472,OFFSET=4)(
 input wire clk,rst,abort,in_valid,input wire[7:0]in_pixel,in_raw,
 input wire[9:0]in_x,input wire[8:0]in_y,input wire[31:0]in_frame_id,
 input wire[10:0]threshold,output reg out_valid,output reg[7:0]out_raw,out_edge,
 output reg[9:0]out_x,output reg[8:0]out_y,output reg[31:0]out_frame_id);
 wire[9:0]lx=in_x-OFFSET;wire[8:0]ly=in_y-OFFSET;
 wire rv;wire[47:0]rows;wire[9:0]rx;wire[8:0]ry;wire[31:0]rf;
 row_window3 #(W,H,16) window(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),
 .in_data({in_raw,in_pixel}),.in_x(lx),.in_y(ly),.in_sof(in_valid&&lx==0&&ly==0),.in_frame_id(in_frame_id),
 .out_valid(rv),.out_rows(rows),.out_x(rx),.out_y(ry),.out_frame_id(rf));
 reg[15:0]l2[0:2],l1[0:2];integer k;
 wire[9:0]right_sum={2'd0,rows[7:0]}+{1'd0,rows[23:16],1'b0}+{2'd0,rows[39:32]};
 wire[9:0]left_sum={2'd0,l2[0][7:0]}+{1'd0,l2[1][7:0],1'b0}+{2'd0,l2[2][7:0]};
 wire[9:0]bottom_sum={2'd0,l2[2][7:0]}+{1'd0,l1[2][7:0],1'b0}+{2'd0,rows[39:32]};
 wire[9:0]top_sum={2'd0,l2[0][7:0]}+{1'd0,l1[0][7:0],1'b0}+{2'd0,rows[7:0]};
 reg signed[10:0]gx0,gy0;reg[10:0]ax1,ay1;wire[11:0]magnitude={1'b0,ax1}+{1'b0,ay1};
 reg v0,v1;reg[7:0]raw0,raw1;reg[9:0]x0,x1;reg[8:0]y0,y1;reg[31:0]f0,f1;
 always @(posedge clk)begin
  if(rst||abort)begin v0<=0;v1<=0;out_valid<=0;end
  else begin
   v0<=rv&&rx>=2&&ry>=2;v1<=v0;out_valid<=v1;
   if(rv)for(k=0;k<3;k=k+1)begin l2[k]<=l1[k];l1[k]<=rows[k*16+:16];end
  end
  gx0<=$signed({1'b0,right_sum})-$signed({1'b0,left_sum});
  gy0<=$signed({1'b0,bottom_sum})-$signed({1'b0,top_sum});
  ax1<=gx0[10]?-gx0:gx0;ay1<=gy0[10]?-gy0:gy0;
  raw0<=l1[1][15:8];x0<=rx-1+OFFSET;y0<=ry-1+OFFSET;f0<=rf;
  raw1<=raw0;x1<=x0;y1<=y0;f1<=f0;
  out_raw<=raw1;out_edge<=(magnitude>={1'b0,threshold})?8'd255:8'd0;
  out_x<=x1;out_y<=y1;out_frame_id<=f1;
 end
endmodule
