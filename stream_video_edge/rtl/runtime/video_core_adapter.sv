`timescale 1ns/1ps
// RAW bypass retains full input. EDGE uses unchanged formal core, cropped5px each side.
// No ready/backpressure path enters the numerical core.
module video_core_adapter #(parameter W=640,H=480)(
 input wire clk,rst,start,edge_view,filter_id,source_valid,input wire[7:0]source_pixel,
 input wire[9:0]source_x,input wire[8:0]source_y,input wire source_done,
 output reg out_valid,output reg[7:0]out_pixel,out_raw,
 output reg[9:0]out_x,output reg[8:0]out_y,output reg out_done,error);
 wire ev,eeof,ce;wire[7:0]ep,er;wire[9:0]ex;wire[8:0]ey;
 edge_core #(W,H) core(.clk(clk),.rst(rst),.abort(start),
 .in_valid(source_valid&&edge_view),.in_pixel(source_pixel),.in_x(source_x),.in_y(source_y),
 .in_sof(source_x==0&&source_y==0),.in_frame_id(32'd0),
 .filter_id(filter_id),.view_edge(1'b1),.epsilon(11'd1024),.edge_threshold(filter_id?11'd128:11'd96),
 .out_valid(ev),.out_pixel(ep),.out_raw(er),.out_edge(),.out_x(ex),.out_y(ey),.out_frame_id(),
 .out_sof(),.out_eol(),.out_eof(eeof),.error(ce));
 // One transfer register separates core coordinates/subtraction from sink checks.
 // It moves valid/data/coordinates/EOF together and does not stall the core.
 always @(posedge clk)begin
  if(rst||start)begin out_valid<=0;out_done<=0;error<=0;out_pixel<=0;out_raw<=0;out_x<=0;out_y<=0;end
  else begin
   out_valid<=edge_view?ev:source_valid;
   out_pixel<=edge_view?ep:source_pixel;
   out_raw<=edge_view?er:source_pixel;
   out_x<=edge_view?(ex-10'd5):source_x;
   out_y<=edge_view?(ey-9'd5):source_y;
   out_done<=edge_view?eeof:source_done;
   error<=edge_view&&ce;
  end
 end
endmodule
