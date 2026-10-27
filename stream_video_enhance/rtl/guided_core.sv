`timescale 1ns/1ps
module guided_core #(parameter integer W=640,H=480,EXTRA_ALIGN=0)(
 input wire clk,rst,abort,input wire [7:0] in_pixel,input wire in_valid,
 input wire [9:0] in_x,input wire [8:0] in_y,input wire in_sof,in_eol,in_eof,input wire [31:0] in_frame_id,
 input wire [10:0] epsilon,input wire [4:0] threshold,input wire [9:0] gain,input wire [1:0] view_mode,
 output wire [7:0] out_pixel,out_raw,out_base,output wire out_valid,
 output wire [9:0] out_x,output wire [8:0] out_y,output wire out_sof,out_eol,out_eof,
 output wire [31:0] out_frame_id,output wire arithmetic_error);

 localparam integer L_ALIGN=core_latency_pkg::L_ALIGN+EXTRA_ALIGN;
 localparam integer L_CORE=core_latency_pkg::L_MOM+core_latency_pkg::L_COEF+core_latency_pkg::L_BOX+
     core_latency_pkg::L_REC+core_latency_pkg::L_ENH+core_latency_pkg::L_LINK+L_ALIGN;
 localparam integer LATENCY=L_CORE;
 initial if(W<16 || W>640 || H<16 || H>480 || EXTRA_ALIGN<0 || EXTRA_ALIGN>1)
   $fatal(1,"illegal guided_core parameters");
 reg [10:0] active_epsilon;reg [4:0] active_threshold;reg [9:0] active_gain;reg [1:0] active_mode;
 wire legal_config=(epsilon==16 || epsilon==64 || epsilon==256 || epsilon==1024) && threshold<=16 && gain<=512;
 always @(posedge clk)begin
   if(rst)begin active_epsilon<=1024;active_threshold<=2;active_gain<=256;active_mode<=2;end
   else if(!abort && in_valid && in_sof && legal_config)begin
     active_epsilon<=epsilon;active_threshold<=threshold;
     active_gain<=(view_mode==2)?10'd256:gain;active_mode<=view_mode;
   end
 end
 wire mv,cv,bv,rv,ev,me,ce,be,re,ee;
 wire [12:0] s1;wire [20:0] s2;
 wire [11:0] a,abar;wire [15:0] b,bbar,base_q8;
 wire [7:0] mc,cc,bc,rc,selected,raw,base;
 wire [9:0] mx,cx,bx,rx,ex;wire [8:0] my,cy,by,ry,ey;
 wire [31:0] mf,cf,bf,rf,ef;
 moments5 #(W,H) mom(.clk(clk),.rst(rst),.abort(abort),.in_valid(in_valid),.in_pixel(in_pixel),.in_x(in_x),.in_y(in_y),.in_sof(in_sof),.in_frame_id(in_frame_id),.out_valid(mv),.out_s1(s1),.out_s2(s2),.out_center(mc),.out_x(mx),.out_y(my),.out_frame_id(mf),.range_error(me));
 coefficient5 coef(.clk(clk),.rst(rst),.abort(abort),.in_valid(mv),.in_s1(s1),.in_s2(s2),.epsilon(active_epsilon),.in_center(mc),.in_x(mx),.in_y(my),.in_frame_id(mf),.out_valid(cv),.out_a(a),.out_b(b),.out_center(cc),.out_x(cx),.out_y(cy),.out_frame_id(cf),.range_error(ce));
 coefficient_box5 #(W,H) box(.clk(clk),.rst(rst),.abort(abort),.in_valid(cv),.in_a(a),.in_b(b),.in_center(cc),.in_x(cx),.in_y(cy),.in_sof(cv && cx==2 && cy==2),.in_frame_id(cf),.out_valid(bv),.out_abar(abar),.out_bbar(bbar),.out_align(bc),.out_x(bx),.out_y(by),.out_frame_id(bf),.range_error(be));
 reconstruct rec(.clk(clk),.rst(rst),.abort(abort),.in_valid(bv),.in_abar(abar),.in_bbar(bbar),.in_align(bc),.in_x(bx),.in_y(by),.in_frame_id(bf),.out_valid(rv),.out_base_q8(base_q8),.out_align(rc),.out_x(rx),.out_y(ry),.out_frame_id(rf),.range_error(re));
 detail_enhance enh(.clk(clk),.rst(rst),.abort(abort),.in_valid(rv),.in_base_q8(base_q8),.in_align(rc),.threshold(active_threshold),.gain(active_gain),.view_mode(active_mode),.in_x(rx),.in_y(ry),.in_frame_id(rf),.out_valid(ev),.out_pixel(selected),.out_raw(raw),.out_base(base),.out_x(ex),.out_y(ey),.out_frame_id(ef),.range_error(ee));
 // A fault at an early cropped coefficient must still invalidate the whole frame.
 // These are valid-aligned stage events, not an output-pixel-only fault flag.
 assign arithmetic_error=!rst && !abort && (me || ce || be || re || ee);
 generate if(EXTRA_ALIGN==0)begin:g_direct
   assign out_valid=ev;
   assign {out_frame_id,out_y,out_x,out_raw,out_base,out_pixel}={ef,ey,ex,raw,base,selected};
 end else begin:g_align
   // Exactly one actual register after enhancement: one clock, not token_pipe(1).
   reg valid;reg [74:0] payload;
   always @(posedge clk)begin
     if(rst || abort)valid<=0;else valid<=ev;
     payload<={ef,ey,ex,raw,base,selected};
   end
   assign out_valid=valid && !rst && !abort;
   assign {out_frame_id,out_y,out_x,out_raw,out_base,out_pixel}=payload;
 end endgenerate
 assign out_sof=out_valid && out_x==4 && out_y==4;
 assign out_eol=out_valid && out_x==W-5;
 assign out_eof=out_valid && out_x==W-5 && out_y==H-5;
 // synthesis translate_off
 reg busy=0;
 always @(posedge clk)begin
   if(rst || abort)busy<=0;
   else begin
     if(out_eof)busy<=0;
     if(in_valid && in_sof)begin
       if(busy && !out_eof)$fatal(1,"new frame before core drain");
       if(!legal_config)$fatal(1,"illegal frame configuration");
       busy<=1;
     end
   end
 end
 initial begin
   if(mom.LATENCY!=core_latency_pkg::L_MOM || coef.LATENCY!=core_latency_pkg::L_COEF ||
      box.LATENCY!=core_latency_pkg::L_BOX || rec.LATENCY!=core_latency_pkg::L_REC ||
      enh.LATENCY!=core_latency_pkg::L_ENH)$fatal(1,"core latency package/module mismatch");
 end
 // synthesis translate_on
endmodule
