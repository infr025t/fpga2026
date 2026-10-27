`timescale 1ns/1ps
// Synchronous block RAM read, one response cycle; no RAM-data reset.
module ingress_fifo #(parameter integer DEPTH=1024)(
  input wire clk,rst,wr_en,input wire [63:0] wr_data,input wire rd_en,
  output reg rd_valid,output reg [63:0] rd_data,
  output wire empty,full,output reg [$clog2(DEPTH+1)-1:0] level,
  output wire overflow
);
  localparam integer AW=(DEPTH<2)?1:$clog2(DEPTH);
  (* ram_style="block" *) reg [63:0] memory[0:DEPTH-1];
  reg [AW-1:0] wp,rp;
  wire pop=rd_en && !empty;
  wire push=wr_en && (!full || pop);
  assign empty=level==0;assign full=level==DEPTH;
  assign overflow=wr_en && full && !pop && !rst;
  initial if(DEPTH<1 || DEPTH>1024)$fatal(1,"illegal ingress FIFO depth");
  always @(posedge clk)begin
    if(!rst)begin
      if(push)begin memory[wp]<=wr_data;wp<=(wp==DEPTH-1)?0:wp+1'b1;end
      if(pop)begin rd_data<=memory[rp];rp<=(rp==DEPTH-1)?0:rp+1'b1;end
    end
    if(rst)begin wp<=0;rp<=0;level<=0;rd_valid<=0;end
    else begin
      rd_valid<=pop;
      case({push,pop})2'b10:level<=level+1'b1;2'b01:level<=level-1'b1;default:begin end endcase
    end
  end
endmodule
