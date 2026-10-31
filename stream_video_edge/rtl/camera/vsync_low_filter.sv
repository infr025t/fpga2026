`timescale 1ns/1ps
// Test candidate: require stable HIGH as well as LOW before changing field state.
// Input is already synchronized; the first-HREF setup margin must be verified.
module vsync_low_filter #(parameter MIN_LOW=64)(
 input wire clk,rst,clear_stats,sync_in,
 output reg sync_out=1,
 output reg[31:0]last_long_low=0,rejected=0,max_rejected=0,last_raw_low=0);
 localparam CW=(MIN_LOW<2)?1:$clog2(MIN_LOW+1);
 reg[CW-1:0]qual_count=0,high_count=0;reg[31:0]low_ticks=0;
 always @(posedge clk)begin
  if(rst)begin
   sync_out<=1;qual_count<=0;high_count<=0;low_ticks<=0;
   last_long_low<=0;rejected<=0;max_rejected<=0;last_raw_low<=0;
  end else begin
   if(!sync_in)begin
    high_count<=0;
    if(low_ticks!=32'hffffffff)low_ticks<=low_ticks+1'b1;
    if(qual_count<MIN_LOW)qual_count<=qual_count+1'b1;
    if(qual_count==MIN_LOW-1)sync_out<=0;
   end else begin
    if(high_count<MIN_LOW)high_count<=high_count+1'b1;
    if(high_count==MIN_LOW-1)sync_out<=1;
    qual_count<=0;low_ticks<=0;
    if(low_ticks!=0)begin
     last_raw_low<=low_ticks;
     if(low_ticks<MIN_LOW)begin
      if(rejected!=32'hffffffff)rejected<=rejected+1'b1;
      if(low_ticks>max_rejected)max_rejected<=low_ticks;
     end else last_long_low<=low_ticks;
    end
   end
   // Capture boundaries clear diagnostic results, never the filter state.
   if(clear_stats)begin last_long_low<=0;rejected<=0;max_rejected<=0;last_raw_low<=0;end
  end
 end
endmodule
