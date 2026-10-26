`timescale 1ns/1ps
module coefficient_box_queue #(parameter integer W=640,H=480)(
 input wire clk,rst,abort,in_valid,input wire [11:0] in_a,input wire [15:0] in_b,input wire [7:0] in_center,
 input wire [9:0] in_x,input wire [8:0] in_y,input wire in_sof,input wire [31:0] in_frame_id,
 output wire out_valid,output wire [11:0] out_abar,output wire [15:0] out_bbar,
 output wire [7:0] out_align,output wire [9:0] out_x,output wire [8:0] out_y,
 output wire [31:0] out_frame_id,output wire range_error);
 // Row t+2; vertical tree t+3..5; difference t+6; accumulation t+7;
 // div25 accepts at t+8 and produces t+12 (including internal link).
 localparam integer LATENCY=12;
 initial if(W<16 || W>640 || H<16 || H>480) $fatal(1,"illegal coefficient_box5 parameters");
 wire rv;wire [139:0] rr;wire [9:0] rx;wire [8:0] ry;wire [31:0] rf;
 row_window5 #(W-4,H-4,28) rows(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),
   .in_data({in_a,in_b}),.in_x(in_x-10'd2),.in_y(in_y-9'd2),
   .in_sof(in_sof),.in_frame_id(in_frame_id),.out_valid(rv),.out_rows(rr),
   .out_x(rx),.out_y(ry),.out_frame_id(rf));
 reg [12:0] pair_a[0:1];reg [11:0] tail_a;
 reg [16:0] pair_b[0:1];reg [15:0] tail_b;
 reg [13:0] four_a;reg [11:0] tail_a2;
 reg [17:0] four_b;reg [15:0] tail_b2;
 reg [14:0] col_a;reg [18:0] col_b;
 reg [14:0] history_a[0:4];reg [18:0] history_b[0:4];
 reg signed [15:0] difference_a;reg signed [19:0] difference_b;
 reg signed [22:0] sum_a,sum_b;
 reg [4:0] vp;
 reg [9:0] xp[0:4];reg [8:0] yp[0:4];reg [31:0] fp[0:4];
 reg [7:0] cp[0:4];
 wire [7:0] queue_center;
 center_delay #(2*(W-4)+2) center_queue(.clk(clk),.rst(rst),.abort(abort),
   .in_valid(in_valid),.in_sof(in_sof),.in_center(in_center),.out_center(queue_center));
 wire signed [22:0] next_a=((xp[3]==0)?23'sd0:sum_a)+{{7{difference_a[15]}},difference_a};
 wire signed [22:0] next_b=((xp[3]==0)?23'sd0:sum_b)+{{3{difference_b[19]}},difference_b};
 reg sum_error;
 integer k;
 always @(posedge clk)begin
   if(rst || abort)begin
     vp<=0;sum_a<=0;sum_b<=0;sum_error<=0;
     for(k=0;k<5;k=k+1)begin history_a[k]<=0;history_b[k]<=0;end
   end else begin
     vp<={vp[3:0],rv};
     if(rv)cp[0]<=queue_center;
     if(vp[2])begin
       difference_a<=$signed({1'b0,col_a})-$signed({1'b0,((xp[2]>=5)?history_a[4]:15'd0)});
       difference_b<=$signed({1'b0,col_b})-$signed({1'b0,((xp[2]>=5)?history_b[4]:19'd0)});
       for(k=1;k<5;k=k+1)begin
         history_a[k]<=(xp[2]==0)?0:history_a[k-1];
         history_b[k]<=(xp[2]==0)?0:history_b[k-1];
       end
       history_a[0]<=col_a;history_b[0]<=col_b;
     end
     if(vp[3])begin
       sum_a<=next_a;sum_b<=next_b;
       sum_error<=next_a<0 || next_a>102300 || next_b<0 || next_b>1632000;
     end
   end
   xp[0]<=rx;yp[0]<=ry;fp[0]<=rf;
   for(k=1;k<=4;k=k+1)begin xp[k]<=xp[k-1];yp[k]<=yp[k-1];fp[k]<=fp[k-1];cp[k]<=cp[k-1];end
   pair_a[0]<={1'b0,rr[16+:12]}+{1'b0,rr[44+:12]};
   pair_a[1]<={1'b0,rr[72+:12]}+{1'b0,rr[100+:12]};tail_a<=rr[128+:12];
   pair_b[0]<={1'b0,rr[0+:16]}+{1'b0,rr[28+:16]};
   pair_b[1]<={1'b0,rr[56+:16]}+{1'b0,rr[84+:16]};tail_b<=rr[112+:16];
   four_a<={1'b0,pair_a[0]}+{1'b0,pair_a[1]};tail_a2<=tail_a;
   four_b<={1'b0,pair_b[0]}+{1'b0,pair_b[1]};tail_b2<=tail_b;
   col_a<={1'b0,four_a}+{3'b0,tail_a2};col_b<={1'b0,four_b}+{3'b0,tail_b2};
 end
 wire window_valid=vp[4] && xp[4]>=4 && yp[4]>=4;
 // Bias in the caller, exactly once. Bad full-width sums are flagged before narrowing.
 wire [16:0] n_a=sum_error ? 17'd0 : sum_a[16:0]+17'd12;
 wire [20:0] n_b=sum_error ? 21'd0 : sum_b[20:0]+21'd12;
 wire av,bv,ae,be,mv;
 div25_pipe #(17,12) divide_a(.clk(clk),.rst(rst),.abort(abort),.in_valid(window_valid),.n(n_a),
   .out_valid(av),.q(out_abar),.range_error(ae));
 div25_pipe #(21,16) divide_b(.clk(clk),.rst(rst),.abort(abort),.in_valid(window_valid),.n(n_b),
   .out_valid(bv),.q(out_bbar),.range_error(be));
 wire [9:0] original_x=xp[4];wire [8:0] original_y=yp[4];
 // local bottom-right (x,y) -> original final center (x,y): +2 then -2.
 wire [59:0] metadata;
 token_pipe #(60,4) align_metadata(.clk(clk),.rst(rst),.abort(abort),.in_valid(window_valid),
   .in_data({sum_error,fp[4],original_y,original_x,cp[4]}),.out_valid(mv),.out_data(metadata));
 assign {out_frame_id,out_y,out_x,out_align}=metadata[58:0];
 assign out_valid=av;
 assign range_error=out_valid && (metadata[59] || ae || be || !bv || !mv);
endmodule
