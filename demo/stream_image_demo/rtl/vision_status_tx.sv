`timescale 1ns/1ps
// Optional VST1 diagnostics. No backpressure connection to the image pipeline.
// Fixed 58 bytes: magic, version, flags, length, 12 uint32 counters, CRC16.
module vision_status_tx #(parameter integer CLKS_PER_BIT=100)(
  input wire clk,rst,start,input wire[7:0]flags,input wire[383:0]snapshot,
  output wire tx,output wire busy
);
  reg active,draining;reg[5:0]index;reg[447:0]body;reg[15:0]crc;
  wire ready;
  wire[7:0]data=(index<56)?body[index*8+:8]:(index==56)?crc[7:0]:crc[15:8];
  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart(clk,rst,active && !draining,data,ready,tx);
  assign busy=active;
  function[15:0]update_crc(input[15:0]c,input[7:0]b);
    reg[15:0]v;integer j;
    begin v=c^{b,8'b0};for(j=0;j<8;j=j+1)v=v[15]?(v<<1)^16'h1021:v<<1;update_crc=v;end
  endfunction
  always @(posedge clk)begin
    if(rst)begin active<=0;draining<=0;index<=0;body<=0;crc<=16'hffff;end
    else if(!active)begin
      if(start)begin
        body<={snapshot,16'd58,flags,8'd1,32'h31545356};
        crc<=16'hffff;index<=0;draining<=0;active<=1;
      end
    end else if(draining)begin if(ready)begin active<=0;draining<=0;end end
    else if(ready)begin
      if(index>=4 && index<56)crc<=update_crc(crc,data);
      if(index==57)draining<=1;else index<=index+1'b1;
    end
  end
endmodule
