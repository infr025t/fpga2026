`timescale 1ns/1ps
module char_normalizer #(parameter ENABLE_SCAN=0)(
 input wire clk,rst,start,frame_we,input wire [14:0] frame_addr,
 input wire scan_en,input wire[14:0]scan_addr,output wire[7:0]scan_data,
 input wire [7:0] frame_data,box_x,box_y,box_w,box_h,roi_x0,roi_y0,roi_x1,roi_y1,
 input wire [1:0] flags,
 output reg busy,done,error,output reg [31:0] cycles,
 output reg pixel_we,output reg [9:0] pixel_addr,output reg [7:0] pixel_data);
 // 原帧不随reset清空；仅闲时接受上载。同步读保持Block RAM推断。
 // 显式五个4KiB bank，避免工具将19200深度扩展为32768。
 reg [14:0] rd_addr; reg [2:0] rd_bank;
 // 分割和归一化串行共用一份小图；扫描持有期间禁止上传及启动归一化。
 wire scan_active=ENABLE_SCAN&&scan_en;
 wire[14:0] selected_read_addr=scan_active?scan_addr:rd_addr;
 wire [7:0] bank_data [0:4];
 wire [7:0] rd_data=bank_data[rd_bank];
 assign scan_data=rd_data;
 genvar bank;
 generate for(bank=0;bank<5;bank=bank+1) begin: frame_banks
  (* ram_style="block" *) reg [7:0] mem [0:4095];
  reg [7:0] q;
  assign bank_data[bank]=q;
  always @(posedge clk) begin
   if(frame_we&&!busy&&!scan_active&&frame_addr<19200&&frame_addr[14:12]==bank)
    mem[frame_addr[11:0]]<=frame_data;
   q<=mem[selected_read_addr[11:0]];
  end
 end endgenerate
 always @(posedge clk) rd_bank<=selected_read_addr[14:12];
 (* ram_style="distributed" *) reg [15:0] hist [0:255];
 reg [7:0] lut [0:255];
 reg [7:0] bx,by,bw,bh,rx0,ry0,rx1,ry1,fl;
 reg [7:0] cx0,cy0,cw,ch,hx,hy,bin,raw,low_a,low_b,high_a,high_b;
 reg [15:0] area,hist_tmp,csum;
 reg [15:0] rank_l,rank_h; reg [6:0] frac_l,frac_h;
 reg [14:0] low100,high100,prod_l,prod_h; reg [7:0] delta_l,delta_h;
 reg [7:0] high,den;
 reg [12:0] fit_x,fit_y;
 reg [4:0] nw,nh,dx0,dy0,canvas_x,canvas_y,ox,oy;
 reg [7:0] sx,sy,sx0,sx1,sy0,sy1;
 reg [4:0] wx,wy; reg [9:0] weight_area; reg [17:0] weighted; reg [22:0] sum;
 reg [15:0] xl,xr,yl,yr;
 reg [7:0] contrast;
 reg div_start; reg [31:0] div_num,div_den;
 wire div_busy,div_done; wire [31:0] div_q,div_r;
 u32_div divider(clk,rst,div_start,div_num,div_den,div_busy,div_done,div_q,div_r);
 localparam IDLE=0,VALIDATE=1,PAD=2,HCLEAR=3,HADDR=4,HWAIT=5,HRAW=6,HGET=7,HWRITE=8,
 RANKL=9,RANKLWAIT=10,RANKH=11,RANKHWAIT=12,SCAN=13,PERCENT=14,HIGHWAIT=15,DENSTART=16,DENWAIT=17,
 LUTSTART=18,LUTWAIT=19,FIT=20,FITWAIT=21,CENTER=22,PIXEL=23,
 XLO=24,XLOWAIT=25,XHI=26,XHIWAIT=27,YLO=28,YLOWAIT=29,YHI=30,YHIWAIT=31,
 SAMPLE=32,READWAIT=33,READLUT=34,WEIGHT=35,MULT=36,ACCUM=37,OUTDIV=38,OUTWAIT=39,EMIT=40,FINISH=41,PDELTA=42,PMUL=43,PSUM=44;
 reg [5:0] state;
 wire [8:0] bxend={1'b0,bx}+{1'b0,bw},byend={1'b0,by}+{1'b0,bh};
 wire [8:0] padded_x0=({1'b0,bx}>({1'b0,rx0}+9'd2))?{1'b0,bx}-9'd2:{1'b0,rx0};
 wire [8:0] padded_y0=({1'b0,by}>({1'b0,ry0}+9'd2))?{1'b0,by}-9'd2:{1'b0,ry0};
 wire [8:0] padded_x1=(bxend+9'd2<{1'b0,rx1})?bxend+9'd2:{1'b0,rx1};
 wire [8:0] padded_y1=(byend+9'd2<{1'b0,ry1})?byend+9'd2:{1'b0,ry1};
 wire [16:0] cum_next={1'b0,csum}+{1'b0,hist[bin]};
 // 百分位插值差/乘/加分拍；所有数值按已验证范围定宽，避免32x32乘法。
 wire [7:0] lut_delta=high-bin;
 wire [15:0] lut_numerator=lut_delta*16'd255+{9'd0,den[7:1]};
 wire [8:0] twice_rem={div_r[7:0],1'b0};
 wire [8:0] rounded_fit={1'b0,div_q[7:0]}+((twice_rem>{1'b0,div_den[7:0]})||((twice_rem=={1'b0,div_den[7:0]})&&div_q[0]));
 wire [15:0] dest_x_hi=(ox+9'd1)*cw,dest_y_hi=(oy+9'd1)*ch;
 // 采样乘法先寄存，下一拍再比较/相减，切断乘法到权重的长路径。
 reg [12:0] sample_left,sample_right,sample_top,sample_bottom;
 wire [15:0] x_min=(sample_right<xr)?sample_right:xr,x_max=(sample_left>xl)?sample_left:xl;
 wire [15:0] y_min=(sample_bottom<yr)?sample_bottom:yr,y_max=(sample_top>yl)?sample_top:yl;
 function [14:0] map_addr(input [7:0] px,input [7:0] py,input rot);
  reg [14:0] a;
  begin a=py*15'd160+px;map_addr=rot?15'd19199-a:a;end
 endfunction
 always @(posedge clk) begin
  if(rst) begin
   state<=IDLE;busy<=0;done<=0;error<=0;cycles<=0;pixel_we<=0;pixel_addr<=0;pixel_data<=0;
   rd_addr<=0;div_start<=0;div_num<=0;div_den<=1;
   bx<=0;by<=0;bw<=0;bh<=0;rx0<=0;ry0<=0;rx1<=0;ry1<=0;fl<=0;
   cx0<=0;cy0<=0;cw<=0;ch<=0;hx<=0;hy<=0;bin<=0;raw<=0;hist_tmp<=0;area<=0;
   low_a<=0;low_b<=0;high_a<=0;high_b<=0;csum<=0;rank_l<=0;rank_h<=0;frac_l<=0;frac_h<=0;
   low100<=0;high100<=0;prod_l<=0;prod_h<=0;delta_l<=0;delta_h<=0;high<=0;den<=16;fit_x<=0;fit_y<=0;nw<=0;nh<=0;dx0<=0;dy0<=0;canvas_x<=0;canvas_y<=0;
   ox<=0;oy<=0;sx<=0;sy<=0;sx0<=0;sx1<=0;sy0<=0;sy1<=0;wx<=0;wy<=0;weight_area<=0;weighted<=0;sum<=0;
   xl<=0;xr<=0;yl<=0;yr<=0;contrast<=0;sample_left<=0;sample_right<=0;sample_top<=0;sample_bottom<=0;
  end else begin
   done<=0;pixel_we<=0;div_start<=0;
   if(busy) cycles<=cycles+1'b1;
   case(state)
    IDLE: if(start&&!scan_active) begin
     bx<=box_x;by<=box_y;bw<=box_w;bh<=box_h;rx0<=roi_x0;ry0<=roi_y0;rx1<=roi_x1;ry1<=roi_y1;fl<={6'd0,flags};
     busy<=1;error<=0;cycles<=0;state<=VALIDATE;
    end
    VALIDATE: begin
     if(bw==0||bh==0||rx0>=rx1||ry0>=ry1||rx1>160||ry1>120||bx<rx0||by<ry0||bxend>{1'b0,rx1}||byend>{1'b0,ry1}) begin
      error<=1;state<=FINISH;
     end else begin cx0<=padded_x0[7:0];cy0<=padded_y0[7:0];cw<=padded_x1-padded_x0;ch<=padded_y1-padded_y0;state<=PAD;end
    end
    // 宽高比例乘积在直方图之前寄存，FIT只比较并选择，避免乘加选择长链。
    PAD: begin fit_x<=cw*13'd30;fit_y<=ch*13'd22;area<=cw*ch;bin<=0;hx<=0;hy<=0;state<=HCLEAR;end
    HCLEAR: begin hist[bin]<=0;if(bin==255) state<=HADDR;else bin<=bin+1'b1;end
    HADDR: begin rd_addr<=map_addr(cx0+hx,cy0+hy,fl[0]);state<=HWAIT;end
    HWAIT: state<=HRAW;
    HRAW: begin raw<=fl[1]?8'd255-rd_data:rd_data;state<=HGET;end
    HGET: begin hist_tmp<=hist[raw];state<=HWRITE;end
    HWRITE: begin
     hist[raw]<=hist_tmp+1'b1;
     if(hx==cw-1) begin hx<=0;if(hy==ch-1) state<=RANKL;else begin hy<=hy+1'b1;state<=HADDR;end end
     else begin hx<=hx+1'b1;state<=HADDR;end
    end
    RANKL: begin div_num<=(area-32'd1)*32'd3;div_den<=100;div_start<=1;state<=RANKLWAIT;end
    RANKLWAIT: if(div_done) begin rank_l<=div_q;frac_l<=div_r;state<=RANKH;end
    RANKH: begin div_num<=(area-32'd1)*32'd85;div_den<=100;div_start<=1;state<=RANKHWAIT;end
    RANKHWAIT: if(div_done) begin rank_h<=div_q;frac_h<=div_r;bin<=0;csum<=0;low_a<=0;low_b<=0;high_a<=0;high_b<=0;state<=SCAN;end
    SCAN: begin
     if(csum<=rank_l&&cum_next>rank_l) low_a<=bin;
     if(csum<=rank_l+1&&cum_next>rank_l+1) low_b<=bin;
     if(csum<=rank_h&&cum_next>rank_h) high_a<=bin;
     if(csum<=rank_h+1&&cum_next>rank_h+1) high_b<=bin;
     csum<=cum_next;if(bin==255) state<=PDELTA;else bin<=bin+1'b1;
    end
    PDELTA: begin delta_l<=low_b-low_a;delta_h<=high_b-high_a;state<=PMUL;end
    PMUL: begin prod_l<=frac_l*delta_l;prod_h<=frac_h*delta_h;state<=PSUM;end
    PSUM: begin low100<=low_a*15'd100+prod_l;high100<=high_a*15'd100+prod_h;state<=PERCENT;end
    PERCENT: begin div_num<={17'd0,high100};div_den<=100;div_start<=1;state<=HIGHWAIT;end
    HIGHWAIT: if(div_done) begin high<=div_q[7:0];state<=DENSTART;end
    DENSTART: begin div_num<={17'd0,high100}-{17'd0,low100};div_den<=100;div_start<=1;state<=DENWAIT;end
    DENWAIT: if(div_done) begin den<=(div_q<16)?8'd16:div_q[7:0];bin<=0;state<=LUTSTART;end
    LUTSTART: begin
     if(bin>=high) begin lut[bin]<=0;if(bin==255) state<=FIT;else bin<=bin+1'b1;end
     else begin div_num<={16'd0,lut_numerator};div_den<=den;div_start<=1;state<=LUTWAIT;end
    end
    LUTWAIT: if(div_done) begin lut[bin]<=(div_q>255)?8'd255:div_q[7:0];bin<=bin+1'b1;state<=LUTSTART;end
    FIT: begin
     if(fit_y<=fit_x) begin nw<=22;nh<=0;div_num<=fit_y;div_den<=cw;end
     else begin nh<=30;nw<=0;div_num<=fit_x;div_den<=ch;end
     div_start<=1;state<=FITWAIT;
    end
    FITWAIT: if(div_done) begin
     if(nw==0) nw<=(rounded_fit==0)?8'd1:rounded_fit[7:0];else nh<=(rounded_fit==0)?8'd1:rounded_fit[7:0];
     state<=CENTER;
    end
    CENTER: begin dx0<=(24-nw)>>1;dy0<=(32-nh)>>1;canvas_x<=0;canvas_y<=0;pixel_addr<=0;state<=PIXEL;end
    PIXEL: begin
     if(canvas_x<dx0||canvas_x>=dx0+nw||canvas_y<dy0||canvas_y>=dy0+nh) begin pixel_data<=0;state<=EMIT;end
     else begin ox<=canvas_x-dx0;oy<=canvas_y-dy0;state<=XLO;end
    end
    XLO: begin div_num<=ox*cw;div_den<=nw;div_start<=1;xl<=ox*cw;xr<=(ox+16'd1)*cw;yl<=oy*ch;yr<=(oy+16'd1)*ch;state<=XLOWAIT;end
    XLOWAIT: if(div_done) begin sx0<=div_q[7:0];state<=XHI;end
    XHI: begin div_num<={16'd0,dest_x_hi}-32'd1;div_den<=nw;div_start<=1;state<=XHIWAIT;end
    XHIWAIT: if(div_done) begin sx1<=div_q[7:0];state<=YLO;end
    YLO: begin div_num<=oy*ch;div_den<=nh;div_start<=1;state<=YLOWAIT;end
    YLOWAIT: if(div_done) begin sy0<=div_q[7:0];state<=YHI;end
    YHI: begin div_num<={16'd0,dest_y_hi}-32'd1;div_den<=nh;div_start<=1;state<=YHIWAIT;end
    YHIWAIT: if(div_done) begin sy1<=div_q[7:0];sx<=sx0;sy<=sy0;sum<=0;state<=SAMPLE;end
    SAMPLE: begin
     rd_addr<=map_addr(cx0+sx,cy0+sy,fl[0]);
     sample_left<=sx*nw;sample_right<=(sx+9'd1)*nw;
     sample_top<=sy*nh;sample_bottom<=(sy+9'd1)*nh;state<=READWAIT;
    end
    READWAIT: state<=READLUT;
    READLUT: begin contrast<=lut[fl[1]?8'd255-rd_data:rd_data];wx<=x_min-x_max;wy<=y_min-y_max;state<=WEIGHT;end
    WEIGHT: begin weight_area<=wx*wy;state<=MULT;end
    MULT: begin weighted<=weight_area*contrast;state<=ACCUM;end
    ACCUM: begin
     sum<=sum+weighted;
     if(sx==sx1) begin sx<=sx0;if(sy==sy1) state<=OUTDIV;else begin sy<=sy+1'b1;state<=SAMPLE;end end
     else begin sx<=sx+1'b1;state<=SAMPLE;end
    end
    OUTDIV: begin div_num<=sum+(area>>1);div_den<=area;div_start<=1;state<=OUTWAIT;end
    OUTWAIT: if(div_done) begin pixel_data<=div_q[7:0];state<=EMIT;end
    EMIT: begin pixel_we<=1;pixel_addr<=canvas_y*10'd24+canvas_x;
     if(canvas_x==23) begin canvas_x<=0;if(canvas_y==31) state<=FINISH;else begin canvas_y<=canvas_y+1'b1;state<=PIXEL;end end
     else begin canvas_x<=canvas_x+1'b1;state<=PIXEL;end
    end
    FINISH: begin busy<=0;done<=1;state<=IDLE;end
    default: begin error<=1;state<=FINISH;end
   endcase
  end
 end
endmodule
