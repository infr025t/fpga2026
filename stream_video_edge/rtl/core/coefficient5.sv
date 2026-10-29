`timescale 1ns/1ps
module coefficient5(
 input wire clk,rst,abort,in_valid,input wire [12:0] in_s1,input wire [20:0] in_s2,input wire [10:0] epsilon,
 input wire [7:0] in_center,input wire [9:0] in_x,input wire [8:0] in_y,input wire [31:0] in_frame_id,
 output wire out_valid,output wire [11:0] out_a,output wire [15:0] out_b,output wire [7:0] out_center,
 output wire [9:0] out_x,output wire [8:0] out_y,output wire [31:0] out_frame_id,output wire range_error);

 // t products; t+1 DSP output; t+2 variance; t+3 denominator;
 // ratio samples t+4 -> t+17; b product t+18/t+19 -> round t+20.
 localparam integer LATENCY=core_latency_pkg::L_COEF;
 (* use_dsp="yes" *) reg [25:0] square0,times25_0,square1,times25_1;
 reg [19:0] eps0,eps1,eps2;
 reg bad0,bad1,bad2,bad3;reg [3:0] vp;
 reg [23:0] variance2,variance3,denominator3;
 wire signed [26:0] variance_full=$signed({1'b0,times25_1})-$signed({1'b0,square1});
 wire legal_epsilon=epsilon==16 || epsilon==64 || epsilon==256 || epsilon==1024;
 always @(posedge clk)begin
   if(rst || abort)vp<=0;
   else vp<={vp[2:0],in_valid};
   square0<=in_s1*in_s1;times25_0<=in_s2*5'd25;
   square1<=square0;times25_1<=times25_0;
   eps0<=legal_epsilon ? epsilon*10'd625 : 20'd10000;
   eps1<=eps0;eps2<=eps1;
   bad0<=!legal_epsilon || in_s1>6375 || in_s2>1625625;
   bad1<=bad0;
   bad2<=bad1 || variance_full<0 || variance_full>10143900;
   variance2<=(variance_full<0 || variance_full>10143900)?24'd0:variance_full[23:0];
   bad3<=bad2;variance3<=variance2;denominator3<=variance2+{4'b0,eps2};
 end
 wire av,ae,mv,me,mdv,errv,meta_valid;wire [11:0] a;wire [15:0] mean;
 wire [16:0] mean_delayed;wire delayed_error;wire [58:0] metadata;
 ratio_q12_pipe ratio(.clk(clk),.rst(rst),.abort(abort),.in_valid(vp[3]),.v(variance3),.den(denominator3),.out_valid(av),.a(a),.range_error(ae));
 wire [20:0] mean_n=(in_s1>6375)?21'd0:({in_s1,8'b0}+21'd12);
 div25_pipe #(21,16) mean_div(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),.n(mean_n),.out_valid(mv),.q(mean),.range_error(me));
 token_pipe #(17,12) delay_mean(.clk(clk),.rst(rst),.abort(abort),.in_valid(mv),.in_data({me,mean}),.out_valid(mdv),.out_data(mean_delayed));
 token_pipe #(1,13) delay_error(.clk(clk),.rst(rst),.abort(abort),.in_valid(vp[3]),.in_data(bad3),.out_valid(errv),.out_data(delayed_error));
 token_pipe #(59,17) delay_metadata(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),.in_data({in_frame_id,in_y,in_x,in_center}),.out_valid(meta_valid),.out_data(metadata));
 (* use_dsp="yes" *) reg [28:0] product0,product1;
 reg [16:0] rounded_b;
 wire [12:0] complement_a=13'd4096-{1'b0,a};
 always @(posedge clk)begin
   product0<=complement_a*mean_delayed[15:0];product1<=product0;
   rounded_b<=({1'b0,product1}+30'd2048)>>12;
 end
 wire [71:0] final_metadata;
 wire bad_parallel=delayed_error || ae || mean_delayed[16] || !mdv || !meta_valid || !errv;
 token_pipe #(72,2) finish_metadata(.clk(clk),.rst(rst),.abort(abort),.in_valid(av),.in_data({bad_parallel,a,metadata}),.out_valid(out_valid),.out_data(final_metadata));
 assign {out_frame_id,out_y,out_x,out_center}=final_metadata[58:0];
 assign range_error=out_valid && (final_metadata[71] || rounded_b>65280);
 assign out_a=range_error?12'd0:final_metadata[70:59];
 assign out_b=range_error?16'd0:rounded_b[15:0];

endmodule
