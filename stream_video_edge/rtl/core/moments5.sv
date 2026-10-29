`timescale 1ns/1ps
module moments5 #(parameter integer W=640,H=480)(
 input wire clk,rst,abort,in_valid,input wire [7:0] in_pixel,
 input wire [9:0] in_x,input wire [8:0] in_y,input wire in_sof,input wire [31:0] in_frame_id,
 output wire out_valid,output wire [12:0] out_s1,output wire [20:0] out_s2,
 output wire [7:0] out_center,output wire [9:0] out_x,output wire [8:0] out_y,
 output wire [31:0] out_frame_id,output wire range_error);
 // Acceptance t: row output t+2, square t+3/t+4, tree t+5..7,
 // signed difference t+8, single-register feedback accumulator t+9.
 localparam integer LATENCY=9;
 initial if(W<16 || W>640 || H<16 || H>480) $fatal(1,"illegal moments5 parameters");
 wire rv;wire [39:0] rr;wire [9:0] rx;wire [8:0] ry;wire [31:0] rf;
 row_window5 #(W,H,8) rows(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),
   .in_data(in_pixel),.in_x(in_x),.in_y(in_y),.in_sof(in_sof),.in_frame_id(in_frame_id),
   .out_valid(rv),.out_rows(rr),.out_x(rx),.out_y(ry),.out_frame_id(rf));
 (* use_dsp="yes" *) reg [15:0] square0[0:4];
 reg [15:0] square1[0:4];reg [7:0] pixel0[0:4],pixel1[0:4];
 reg [8:0] pair1[0:1];reg [7:0] tail1;
 reg [16:0] pair2[0:1];reg [15:0] tail2;
 reg [9:0] four1;reg [7:0] tail1b;
 reg [17:0] four2;reg [15:0] tail2b;
 reg [10:0] col1;reg [18:0] col2;
 reg [10:0] history1[0:4];reg [18:0] history2[0:4];
 reg signed [11:0] difference1;reg signed [19:0] difference2;
 reg signed [22:0] sum1,sum2;
 reg [9:0] xp[0:6];reg [8:0] yp[0:6];reg [31:0] fp[0:6];
 wire signed [22:0] next1=((xp[5]==0)?23'sd0:sum1)+{{11{difference1[11]}},difference1};
 wire signed [22:0] next2=((xp[5]==0)?23'sd0:sum2)+{{3{difference2[19]}},difference2};
 reg error6;
 reg [6:0] vp;
 reg [7:0] cp[0:6],center0,center1;
 integer k;
 always @(posedge clk)begin
   if(rst || abort)begin
     vp<=0;sum1<=0;sum2<=0;error6<=0;center0<=0;center1<=0;
     for(k=0;k<5;k=k+1)begin history1[k]<=0;history2[k]<=0;end
   end else begin
     vp<={vp[5:0],rv};
     if(rv)begin
       if(rx==0)begin center0<=rr[16+:8];center1<=0;cp[0]<=0;end
       else begin center0<=rr[16+:8];center1<=center0;cp[0]<=center1;end
     end
     if(vp[4])begin
       difference1<=$signed({1'b0,col1})-$signed({1'b0,((xp[4]>=5)?history1[4]:11'd0)});
       difference2<=$signed({1'b0,col2})-$signed({1'b0,((xp[4]>=5)?history2[4]:19'd0)});
       for(k=1;k<5;k=k+1)begin
         history1[k]<=(xp[4]==0)?0:history1[k-1];
         history2[k]<=(xp[4]==0)?0:history2[k-1];
       end
       history1[0]<=col1;history2[0]<=col2;
     end
     if(vp[5])begin
       sum1<=next1;sum2<=next2;
       error6<=next1<0 || next1>6375 || next2<0 || next2>1625625;
     end
   end
   xp[0]<=rx;yp[0]<=ry;fp[0]<=rf;
   for(k=1;k<=6;k=k+1)begin xp[k]<=xp[k-1];yp[k]<=yp[k-1];fp[k]<=fp[k-1];cp[k]<=cp[k-1];end
   for(k=0;k<5;k=k+1)begin
     square0[k]<=rr[k*8+:8]*rr[k*8+:8];square1[k]<=square0[k];
     pixel0[k]<=rr[k*8+:8];pixel1[k]<=pixel0[k];
   end
   pair1[0]<={1'b0,pixel1[0]}+{1'b0,pixel1[1]};
   pair1[1]<={1'b0,pixel1[2]}+{1'b0,pixel1[3]};tail1<=pixel1[4];
   pair2[0]<={1'b0,square1[0]}+{1'b0,square1[1]};
   pair2[1]<={1'b0,square1[2]}+{1'b0,square1[3]};tail2<=square1[4];
   four1<={1'b0,pair1[0]}+{1'b0,pair1[1]};tail1b<=tail1;
   four2<={1'b0,pair2[0]}+{1'b0,pair2[1]};tail2b<=tail2;
   col1<={1'b0,four1}+{3'b0,tail1b};col2<={1'b0,four2}+{3'b0,tail2b};
 end
 assign out_valid=vp[6] && xp[6]>=4 && yp[6]>=4 && !rst && !abort;
 assign range_error=out_valid && error6;
 assign out_s1=error6?13'd0:sum1[12:0];assign out_s2=error6?21'd0:sum2[20:0];
 assign out_center=cp[6];assign out_x=xp[6]-10'd2;assign out_y=yp[6]-9'd2;assign out_frame_id=fp[6];
endmodule
