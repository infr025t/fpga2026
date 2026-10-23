`timescale 1ns/1ps
// Bounded single-clock ingress FIFO after the external AL422 clock crossing.
// DEPTH need not be a power of two. Full+pop can accept a replacement sample.
module pixel_fifo #(parameter integer WIDTH=9,DEPTH=16)(
  input wire clk,rst,in_valid,input wire[WIDTH-1:0]in_data,
  output wire in_ready,output wire out_valid,output wire[WIDTH-1:0]out_data,
  input wire out_ready,output reg overflow,
  output reg[$clog2(DEPTH+1)-1:0]level
);
  localparam integer AW=(DEPTH<2)?1:$clog2(DEPTH);
  reg[WIDTH-1:0]memory[0:DEPTH-1];reg[AW-1:0]wp,rp;
  assign out_valid=level!=0;
  assign in_ready=(level<DEPTH) || (out_valid && out_ready);
  assign out_data=memory[rp];
  wire push=in_valid && in_ready,pop=out_valid && out_ready;
  always @(posedge clk)begin
    if(rst)begin wp<=0;rp<=0;level<=0;overflow<=0;end
    else begin
      overflow<=in_valid && !in_ready;
      if(push)begin memory[wp]<=in_data;wp<=(wp==DEPTH-1)?0:wp+1'b1;end
      if(pop)rp<=(rp==DEPTH-1)?0:rp+1'b1;
      case({push,pop})2'b10:level<=level+1'b1;2'b01:level<=level-1'b1;default:level<=level;endcase
    end
  end
endmodule
