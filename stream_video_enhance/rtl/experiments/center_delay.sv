`timescale 1ns/1ps
// Experiment B: D preceding valid tokens, followed by the row helper's
// two-clock latency. Prefetch next slot: read and write addresses never coincide.
// Warmup data is unobservable until the second 5x5 window is complete.
module center_delay #(parameter integer DEPTH=1274)(
 input wire clk,rst,abort,in_valid,in_sof,input wire [7:0] in_center,
 output wire [7:0] out_center);
 localparam integer AW=$clog2(DEPTH);
 (* ram_style="block" *) reg [7:0] memory[0:DEPTH-1];
 reg [AW-1:0] pointer=0;
 wire [AW-1:0] address=in_sof ? {AW{1'b0}} : pointer;
 wire [AW-1:0] next_address=(address==DEPTH-1)?{AW{1'b0}}:address+1'b1;
 reg [7:0] prefetch,output0,output1,output2;
 always @(posedge clk)begin
   if(in_valid && !rst && !abort)begin
     memory[address]<=in_center;
     prefetch<=memory[next_address];
   end
   if(rst || abort)pointer<=0;
   else if(in_valid)pointer<=next_address;
   output0<=prefetch;output1<=output0;output2<=output1;
 end
 assign out_center=output2;
endmodule
