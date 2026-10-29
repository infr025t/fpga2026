`timescale 1ns/1ps
module reconstruct(
 input wire clk,rst,abort,in_valid,input wire [11:0] in_abar,input wire [15:0] in_bbar,input wire [7:0] in_align,
 input wire [9:0] in_x,input wire [8:0] in_y,input wire [31:0] in_frame_id,
 output wire out_valid,output wire [15:0] out_base_q8,output wire [7:0] out_align,
 output wire [9:0] out_x,output wire [8:0] out_y,output wire [31:0] out_frame_id,output wire range_error);

 // Full U20 product t/t+1; Q12->Q8 round and U17 add t+2; clamp t+3.
 localparam integer LATENCY=core_latency_pkg::L_REC;
 (* use_dsp="yes" *) reg [19:0] product0,product1;
 reg [15:0] b0,b1;reg [16:0] sum2;reg [15:0] base3;
 wire [20:0] rounded_product=({1'b0,product1}+21'd8)>>4;
 always @(posedge clk)begin
   product0<=in_abar*in_align;product1<=product0;b0<=in_bbar;b1<=b0;
   sum2<=rounded_product[16:0]+{1'b0,b1};
   base3<=(sum2>65280)?16'd65280:sum2[15:0];
 end
 wire [59:0] metadata;
 token_pipe #(60,LATENCY) delay_metadata(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),
 .in_data({(in_abar>4092 || in_bbar>65280),in_frame_id,in_y,in_x,in_align}),.out_valid(out_valid),.out_data(metadata));
 assign {out_frame_id,out_y,out_x,out_align}=metadata[58:0];
 assign range_error=out_valid && metadata[59];
 assign out_base_q8=range_error?16'd0:base3;

endmodule
