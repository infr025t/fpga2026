`timescale 1ns/1ps
module capture_fault_latch(input wire clk,rst,input wire[7:0]live_error,
 input wire[255:0]live_timing,output wire[7:0]observed_error,output wire[255:0]observed_timing);
 reg[7:0]first_error=0;
 reg[255:0]first_timing=0;
 assign observed_error=first_error!=0?first_error:live_error;
 assign observed_timing=first_error!=0?first_timing:live_timing;
 always @(posedge clk)begin
  if(rst)begin first_error<=0;first_timing<=0;end
  else if(first_error==0 && live_error!=0)begin first_error<=live_error;first_timing<=live_timing;end
 end
endmodule
