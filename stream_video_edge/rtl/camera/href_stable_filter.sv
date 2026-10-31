`timescale 1ns/1ps
// Input has already crossed a two-flop synchronizer.
// Both transitions require a sustained opposite level; a short LOW within a
// true row cannot create an extra row-complete event.
module href_stable_filter #(parameter integer STABLE_CYCLES=64)(
 input wire clk,rst,sync_in,output reg sync_out=0);
 localparam CW=(STABLE_CYCLES<2)?1:$clog2(STABLE_CYCLES+1);
 reg[CW-1:0]opposite_count=0;
 always @(posedge clk)begin
  if(rst)begin sync_out<=0;opposite_count<=0;end
  else if(sync_in==sync_out)opposite_count<=0;
  else if(opposite_count==STABLE_CYCLES-1)begin sync_out<=sync_in;opposite_count<=0;end
  else opposite_count<=opposite_count+1'b1;
 end
 initial if(STABLE_CYCLES<1)$fatal(1,"STABLE_CYCLES must be positive");
endmodule
