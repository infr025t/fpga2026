`timescale 1ns/1ps
module detail_enhance(
 input wire clk,rst,abort,in_valid,input wire [15:0] in_base_q8,input wire [7:0] in_align,
 input wire [4:0] threshold,input wire [9:0] gain,input wire [1:0] view_mode,
 input wire [9:0] in_x,input wire [8:0] in_y,input wire [31:0] in_frame_id,
 output wire out_valid,output wire [7:0] out_pixel,out_raw,out_base,
 output wire [9:0] out_x,output wire [8:0] out_y,output wire [31:0] out_frame_id,output wire range_error);

 // D t; registered magnitude/sign t+1; soft limit t+2;
 // signed full multiply t+3/t+4; ties-away t+5; add t+6; select t+7.
 localparam integer LATENCY=core_latency_pkg::L_ENH;
 reg signed [16:0] detail0;reg [4:0] threshold0;
 reg [9:0] gain0,gain_mag,gain1;reg signed [13:0] residual1;
 reg [16:0] magnitude1;reg negative1;reg [4:0] threshold1;
 (* use_dsp="yes" *) reg signed [24:0] product2,product3;
 reg signed [17:0] enhanced4,sum5;
 reg [15:0] base_pipe[0:5];
 reg [7:0] enhanced_pixel6;
 wire [16:0] magnitude0=detail0[16] ? -detail0 : detail0;
 wire [16:0] threshold_q8={4'b0,threshold1,8'b0};
 wire [16:0] excess0=(magnitude1>threshold_q8)?magnitude1-threshold_q8:17'd0;
 wire [13:0] limited0=(excess0>4096)?14'd4096:excess0[13:0];
 wire [24:0] absolute_product=product3[24] ? -product3 : product3;
 wire [25:0] rounded_magnitude=({1'b0,absolute_product}+26'd128)>>8;
 wire [16:0] clipped_sum=(sum5<0)?17'd0:(sum5>65280)?17'd65280:sum5[16:0];
 integer k;
 always @(posedge clk)begin
   detail0<=$signed({1'b0,in_align,8'b0})-$signed({1'b0,in_base_q8});threshold0<=threshold;
   magnitude1<=magnitude0;negative1<=detail0[16];threshold1<=threshold0;
   gain0<=(view_mode==2)?10'd256:gain;gain_mag<=gain0;gain1<=gain_mag;
   residual1<=negative1 ? -$signed(limited0) : $signed(limited0);
   // G=512 must remain positive: the leading zero is part of the signed operand.
   product2<=$signed({1'b0,gain1})*residual1;product3<=product2;
   enhanced4<=product3[24] ? -$signed(rounded_magnitude[17:0]) : $signed(rounded_magnitude[17:0]);
   base_pipe[0]<=in_base_q8;for(k=1;k<6;k=k+1)base_pipe[k]<=base_pipe[k-1];
   sum5<=$signed({2'b0,base_pipe[5]})+enhanced4;
   enhanced_pixel6<=(clipped_sum+17'd128)>>8;
 end
 wire [77:0] metadata;wire [15:0] aligned_base;wire [1:0] aligned_mode;
 token_pipe #(78,LATENCY) delay_metadata(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),
 .in_data({(in_base_q8>65280 || threshold>16 || gain>512),view_mode,in_base_q8,in_frame_id,in_y,in_x,in_align}),.out_valid(out_valid),.out_data(metadata));
 assign {aligned_mode,aligned_base,out_frame_id,out_y,out_x,out_raw}=metadata[76:0];
 assign range_error=out_valid && metadata[77];
 wire [16:0] rounded_base={1'b0,aligned_base}+17'd128;
 assign out_base=rounded_base[15:8];
 assign out_pixel=range_error?8'd0:(aligned_mode==0)?out_raw:(aligned_mode==1)?out_base:enhanced_pixel6;

endmodule
