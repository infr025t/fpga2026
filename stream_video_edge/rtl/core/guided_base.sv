`timescale 1ns/1ps
module guided_base #(parameter W=640,H=480)(
 input wire clk,rst,abort,in_valid,input wire[7:0]in_pixel,input wire[9:0]in_x,
 input wire[8:0]in_y,input wire in_sof,input wire[31:0]in_frame_id,input wire[10:0]epsilon,
 output reg out_valid,output reg[7:0]out_pixel,out_raw,output reg[9:0]out_x,
 output reg[8:0]out_y,output reg[31:0]out_frame_id,output wire error);
 wire mv,cv,bv,rv,me,ce,be,re;wire[12:0]s1;wire[20:0]s2;
 wire[11:0]a,abar;wire[15:0]b,bbar,q8;wire[7:0]mc,cc,bc,rc;
 wire[9:0]mx,cx,bx,rx;wire[8:0]my,cy,by,ry;wire[31:0]mf,cf,bf,rf;
 moments5 #(W,H) mom(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),.in_pixel(in_pixel),.in_x(in_x),.in_y(in_y),.in_sof(in_sof),.in_frame_id(in_frame_id),.out_valid(mv),.out_s1(s1),.out_s2(s2),.out_center(mc),.out_x(mx),.out_y(my),.out_frame_id(mf),.range_error(me));
 coefficient5 coef(.clk(clk),.rst(rst),.abort(abort),.in_valid(mv),.in_s1(s1),.in_s2(s2),.epsilon(epsilon),.in_center(mc),.in_x(mx),.in_y(my),.in_frame_id(mf),.out_valid(cv),.out_a(a),.out_b(b),.out_center(cc),.out_x(cx),.out_y(cy),.out_frame_id(cf),.range_error(ce));
 coefficient_box5 #(W,H) box(.clk(clk),.rst(rst),.abort(abort),.in_valid(cv),.in_a(a),.in_b(b),.in_center(cc),.in_x(cx),.in_y(cy),.in_sof(cv&&cx==2&&cy==2),.in_frame_id(cf),.out_valid(bv),.out_abar(abar),.out_bbar(bbar),.out_align(bc),.out_x(bx),.out_y(by),.out_frame_id(bf),.range_error(be));
 reconstruct rec(.clk(clk),.rst(rst),.abort(abort),.in_valid(bv),.in_abar(abar),.in_bbar(bbar),.in_align(bc),.in_x(bx),.in_y(by),.in_frame_id(bf),.out_valid(rv),.out_base_q8(q8),.out_align(rc),.out_x(rx),.out_y(ry),.out_frame_id(rf),.range_error(re));
 wire[16:0]rounded={1'b0,q8}+17'd128;
 always @(posedge clk)begin
  if(rst||abort)out_valid<=0;else out_valid<=rv;
  out_pixel<=rounded[15:8];out_raw<=rc;out_x<=rx;out_y<=ry;out_frame_id<=rf;
 end
 assign error=!rst&&!abort&&(me||ce||be||re);
endmodule
