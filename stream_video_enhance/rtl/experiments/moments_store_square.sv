`timescale 1ns/1ps
module moments_store_square #(parameter integer W=640,H=480)(
 input wire clk,rst,abort,in_valid,input wire [7:0] in_pixel,
 input wire [9:0] in_x,input wire [8:0] in_y,input wire in_sof,input wire [31:0] in_frame_id,
 output wire out_valid,output wire [12:0] out_s1,output wire [20:0] out_s2,
 output wire [7:0] out_center,output wire [9:0] out_x,output wire [8:0] out_y,
 output wire [31:0] out_frame_id,output wire range_error);
 // Experiment A: move the two square registers before five 24-bit row banks.
 // Same external latency (9), II=1, arithmetic, window and center semantics.
 localparam integer LATENCY=9;
 (* use_dsp="yes" *) reg [15:0] square0;
 reg [23:0] presquare;
 reg [7:0] pixel0;
 reg [1:0] pv,ps;
 reg [9:0] px[0:1];reg [8:0] py[0:1];reg [31:0] pf[0:1];
 always @(posedge clk)begin
   square0<=in_pixel*in_pixel;pixel0<=in_pixel;presquare<={square0,pixel0};
   if(rst || abort)begin pv<=0;ps<=0;end
   else begin pv<={pv[0],in_valid};ps<={ps[0],in_sof};end
   px[0]<=in_x;px[1]<=px[0];py[0]<=in_y;py[1]<=py[0];pf[0]<=in_frame_id;pf[1]<=pf[0];
 end
 wire rv;wire [119:0] rr;wire [9:0] rx;wire [8:0] ry;wire [31:0] rf;
 row_window5 #(W,H,24) rows(.clk(clk),.rst(rst),.abort(abort),.in_valid(pv[1]),
   .in_data(presquare),.in_x(px[1]),.in_y(py[1]),.in_sof(ps[1]),.in_frame_id(pf[1]),
   .out_valid(rv),.out_rows(rr),.out_x(rx),.out_y(ry),.out_frame_id(rf));
 reg [8:0] pair1[0:1];reg [7:0] tail1;
 reg [16:0] pair2[0:1];reg [15:0] tail2;
 reg [9:0] four1;reg [7:0] tail1b;
 reg [17:0] four2;reg [15:0] tail2b;
 reg [10:0] col1;reg [18:0] col2;
 reg [10:0] history1[0:4];reg [18:0] history2[0:4];
 reg signed [11:0] difference1;reg signed [19:0] difference2;
 reg signed [22:0] sum1,sum2;
 reg [9:0] xp[0:4];reg [8:0] yp[0:4];reg [31:0] fp[0:4];
 wire signed [22:0] next1=((xp[3]==0)?23'sd0:sum1)+{{11{difference1[11]}},difference1};
 wire signed [22:0] next2=((xp[3]==0)?23'sd0:sum2)+{{3{difference2[19]}},difference2};
 reg error6;
 reg [4:0] vp;
 reg [7:0] cp[0:4],center0,center1;
 integer k;
 always @(posedge clk)begin
   if(rst || abort)begin
     vp<=0;sum1<=0;sum2<=0;error6<=0;center0<=0;center1<=0;
     for(k=0;k<5;k=k+1)begin history1[k]<=0;history2[k]<=0;end
   end else begin
     vp<={vp[3:0],rv};
     if(rv)begin
       if(rx==0)begin center0<=rr[48+:8];center1<=0;cp[0]<=0;end
       else begin center0<=rr[48+:8];center1<=center0;cp[0]<=center1;end
     end
     if(vp[2])begin
       difference1<=$signed({1'b0,col1})-$signed({1'b0,((xp[2]>=5)?history1[4]:11'd0)});
       difference2<=$signed({1'b0,col2})-$signed({1'b0,((xp[2]>=5)?history2[4]:19'd0)});
       for(k=1;k<5;k=k+1)begin
         history1[k]<=(xp[2]==0)?0:history1[k-1];
         history2[k]<=(xp[2]==0)?0:history2[k-1];
       end
       history1[0]<=col1;history2[0]<=col2;
     end
     if(vp[3])begin
       sum1<=next1;sum2<=next2;
       error6<=next1<0 || next1>6375 || next2<0 || next2>1625625;
     end
   end
   xp[0]<=rx;yp[0]<=ry;fp[0]<=rf;
   for(k=1;k<=4;k=k+1)begin xp[k]<=xp[k-1];yp[k]<=yp[k-1];fp[k]<=fp[k-1];cp[k]<=cp[k-1];end
   pair1[0]<={1'b0,rr[0+:8]}+{1'b0,rr[24+:8]};
   pair1[1]<={1'b0,rr[48+:8]}+{1'b0,rr[72+:8]};tail1<=rr[96+:8];
   pair2[0]<={1'b0,rr[8+:16]}+{1'b0,rr[32+:16]};
   pair2[1]<={1'b0,rr[56+:16]}+{1'b0,rr[80+:16]};tail2<=rr[104+:16];
   four1<={1'b0,pair1[0]}+{1'b0,pair1[1]};tail1b<=tail1;
   four2<={1'b0,pair2[0]}+{1'b0,pair2[1]};tail2b<=tail2;
   col1<={1'b0,four1}+{3'b0,tail1b};col2<={1'b0,four2}+{3'b0,tail2b};
 end
 assign out_valid=vp[4] && xp[4]>=4 && yp[4]>=4 && !rst && !abort;
 assign range_error=out_valid && error6;
 assign out_s1=error6?13'd0:sum1[12:0];assign out_s2=error6?21'd0:sum2[20:0];
 assign out_center=cp[4];assign out_x=xp[4]-10'd2;assign out_y=yp[4]-9'd2;assign out_frame_id=fp[4];
endmodule
