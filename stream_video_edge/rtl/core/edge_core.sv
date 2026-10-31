`timescale 1ns/1ps
// Gaussian3 -> Sobel3 only. Keep the established5px crop and metadata contract.
module edge_core #(parameter W=640,H=480)(
 input wire clk,rst,abort,in_valid,input wire[7:0]in_pixel,input wire[9:0]in_x,
 input wire[8:0]in_y,input wire in_sof,input wire[31:0]in_frame_id,
 input wire view_edge,input wire[10:0]edge_threshold,
 output wire out_valid,output wire[7:0]out_pixel,out_raw,out_edge,
 output wire[9:0]out_x,output wire[8:0]out_y,output wire[31:0]out_frame_id,
 output wire out_sof,out_eol,out_eof,output reg error);
 reg saved_view=0;reg[10:0]saved_threshold=128;
 wire av;wire[7:0]ap,ar;wire[9:0]ax;wire[8:0]ay;wire[31:0]af;
 always @(posedge clk)begin
  if(rst||abort)begin saved_view<=0;saved_threshold<=128;error<=0;end
  else if(in_valid&&in_sof)begin
   saved_view<=view_edge;saved_threshold<=edge_threshold;error<=edge_threshold>2040;
  end
 end
 gaussian3 #(W,H) gaussian(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),
 .in_pixel(in_pixel),.in_x(in_x),.in_y(in_y),.in_sof(in_sof),.in_frame_id(in_frame_id),
 .out_valid(av),.out_pixel(ap),.out_raw(ar),.out_x(ax),.out_y(ay),.out_frame_id(af));
 wire pv=av&&ax>=4&&ax<=W-5&&ay>=4&&ay<=H-5;
 sobel3 #(W-8,H-8,4) sobel(.clk(clk),.rst(rst),.abort(abort),.in_valid(pv),
 .in_pixel(ap),.in_raw(ar),.in_x(ax),.in_y(ay),.in_frame_id(af),.threshold(saved_threshold),
 .out_valid(out_valid),.out_raw(out_raw),.out_edge(out_edge),.out_x(out_x),.out_y(out_y),.out_frame_id(out_frame_id));
 assign out_pixel=saved_view?out_edge:out_raw;
 assign out_sof=out_valid&&out_x==5&&out_y==5;
 assign out_eol=out_valid&&out_x==W-6;
 assign out_eof=out_valid&&out_x==W-6&&out_y==H-6;
 initial if(W<16||H<16||W>640||H>480)$fatal(1,"illegal edge dimensions");
endmodule
