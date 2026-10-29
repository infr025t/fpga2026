`timescale 1ns/1ps
// Test-only 12 Mbaud 8N1 from 100 MHz. Fractional 3/25 bit enable;
// bit boundaries have <10ns quantization error. No generated clock/CDC.
module uart_fast_tx(input wire clk,rst,valid,input wire[7:0]data,
 output wire ready,output reg tx);
 reg active;reg[4:0]phase;reg[3:0]bit_index;reg[9:0]bits;
 assign ready=!active;
 always @(posedge clk)begin
  if(rst)begin active<=0;tx<=1;phase<=0;bit_index<=0;bits<=10'h3ff;end
  else if(!active)begin
   if(valid)begin active<=1;tx<=0;bits<={1'b1,data,1'b0};phase<=0;bit_index<=0;end
  end else if(phase>=22)begin
   phase<=phase-22;
   if(bit_index==9)begin active<=0;tx<=1;end
   else begin bits<={1'b1,bits[9:1]};tx<=bits[1];bit_index<=bit_index+1'b1;end
  end else phase<=phase+3;
 end
endmodule
