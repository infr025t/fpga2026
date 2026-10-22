`timescale 1ns/1ps
// Single-clock 8N1 transmitter. A byte is accepted only on valid && ready.
module uart_tx #(parameter integer CLKS_PER_BIT=100)(
  input wire clk,rst,valid, input wire [7:0] data,
  output wire ready, output reg tx
);
  localparam integer CW=(CLKS_PER_BIT<2)?1:$clog2(CLKS_PER_BIT);
  reg [CW-1:0] ticks;
  reg [3:0] bit_index;
  reg [9:0] bits;
  reg active;
  assign ready=~active;
  always @(posedge clk) begin
    if(rst) begin tx<=1; active<=0; ticks<=0; bit_index<=0; bits<=10'h3ff; end
    else if(!active) begin
      tx<=1;
      if(valid) begin bits<={1'b1,data,1'b0}; tx<=0; active<=1; ticks<=0; bit_index<=0; end
    end else if(ticks==CLKS_PER_BIT-1) begin
      ticks<=0;
      if(bit_index==9) begin active<=0; tx<=1; end
      else begin bit_index<=bit_index+1'b1; bits<={1'b1,bits[9:1]}; tx<=bits[1]; end
    end else ticks<=ticks+1'b1;
  end
endmodule
