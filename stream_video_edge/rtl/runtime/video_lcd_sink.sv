`timescale 1ns/1ps
// RAW/EDGE display consumer. No ready signal is returned to the camera.
module video_lcd_sink #(
  parameter integer W=640,H=480,PW=800,PH=480,DEPTH=64,CLK_HZ=100000000
)(
  input wire clk,rst,start,source_valid,crop_edge,input wire[7:0]source_pixel,
  input wire[9:0]source_x,input wire[8:0]source_y,input wire source_done,source_error,
  output wire ready,busy,output reg done,output reg[7:0]error,
  output wire initialized,output reg background_done,
  output reg[31:0]received,painted,output wire[31:0]input_crc,output_crc,
  output reg[31:0]frames,
  output wire[7:0]lcd_data,output wire lcd_cs_n,lcd_rs,lcd_wr_n,lcd_rd_n,lcd_reset_n,lcd_bl
);
  localparam integer LEFT=(PW-W)/2,TOP=(PH-H)/2,AW=$clog2(DEPTH);
  localparam WAIT_INIT=0,BEGIN_CLEAR=1,CLEAR=2,IDLE=3,BEGIN_FRAME=4,FRAME=5,FAULT=6;
  reg[2:0]state;
  (* ram_style="distributed" *) reg[7:0]queue[0:DEPTH-1];
  reg[AW-1:0]wp,rp;reg[AW:0]used;
  reg active_crop;
  wire[9:0]frame_w=active_crop?W-10:W;
  wire[8:0]frame_h=active_crop?H-10:H;
  wire[31:0]frame_pixels=active_crop?(W-10)*(H-10):W*H;
  reg[9:0]expected_x;reg[8:0]expected_y;
  reg source_finished,paint_finished;
  reg[31:0]rx_crc,tx_crc;
  wire frame_active=state==BEGIN_FRAME || state==FRAME;
  wire[7:0]head=queue[rp];
  wire iv,irs,reset_pin,word_ready,word_done;
  wire[15:0]iw,pw;
  wire pv,prs,paint_ready,paint_done,paint_error,paint_busy,pixel_ready;
  wire is_clear=state==BEGIN_CLEAR || state==CLEAR;
  wire pixel_valid=(state==CLEAR) || (state==FRAME && used!=0);
  wire[15:0]rgb=is_clear?16'd0:{head[7:3],head[7:2],head[7:3]};
  wire pop=state==FRAME && used!=0 && pixel_ready;
  wire coordinates_ok=source_x==expected_x && source_y==expected_y;
  wire push=frame_active && source_valid && received<frame_pixels && coordinates_ok && (used<DEPTH || pop);
  assign ready=state==IDLE && !rst && error==0 && active_crop==crop_edge;
  assign busy=!ready;
  assign lcd_reset_n=reset_pin && !rst;
  assign lcd_bl=initialized && background_done && !rst;
  assign input_crc=~rx_crc;assign output_crc=~tx_crc;
  function automatic[31:0]crc_byte(input[31:0]v,input[7:0]b);
    reg[31:0]t;integer k;begin t=v^b;for(k=0;k<8;k=k+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1);crc_byte=t;end
  endfunction
  nt35510_init #(.CLK_HZ(CLK_HZ)) initialize(
    .clk(clk),.rst(rst),.word_ready(word_ready && !initialized),.word_done(word_done),
    .word_valid(iv),.word(iw),.word_rs(irs),.lcd_reset_n(reset_pin),.init_done(initialized));
  nt35510_window_writer #(.PANEL_W(PW),.PANEL_H(PH)) painter(
    .clk(clk),.rst(rst || !initialized || state==FAULT),
    .start_valid((state==BEGIN_CLEAR || state==BEGIN_FRAME) && !rst),.start_ready(paint_ready),
    .x_start(is_clear?16'd0:16'(LEFT+(active_crop?5:0))),.x_end(is_clear?16'(PW-1):16'(LEFT+W-1-(active_crop?5:0))),
    .y_start(is_clear?16'd0:16'(TOP+(active_crop?5:0))),.y_end(is_clear?16'(PH-1):16'(TOP+H-1-(active_crop?5:0))),
    .pixel_valid(pixel_valid && !rst),.pixel_rgb565(rgb),.pixel_ready(pixel_ready),
    .word_valid(pv),.word(pw),.word_rs(prs),.word_ready(word_ready && initialized),.word_done(word_done),
    .busy(paint_busy),.done(paint_done),.error(paint_error),.pixels_accepted());
  nt35510_bus8 #(.SETUP_CYCLES(4),.LOW_CYCLES(5),.HOLD_CYCLES(3),.GAP_CYCLES(2)) bus(
    .clk(clk),.rst(rst),.in_valid(initialized?pv:iv),.in_word(initialized?pw:iw),.in_rs(initialized?prs:irs),
    .in_ready(word_ready),.lcd_data(lcd_data),.lcd_cs_n(lcd_cs_n),.lcd_rs(lcd_rs),
    .lcd_wr_n(lcd_wr_n),.lcd_rd_n(lcd_rd_n),.word_done(word_done));
  initial if(W<1 || H<1 || W>640 || H>480 || PW<W || PH<H || DEPTH<2 || (DEPTH&(DEPTH-1))!=0)
    $fatal(1,"invalid RAW display dimensions/queue");
  always @(posedge clk or posedge rst)begin
    if(rst)begin
      active_crop<=0;state<=WAIT_INIT;background_done<=0;done<=0;error<=0;wp<=0;rp<=0;used<=0;
      received<=0;painted<=0;frames<=0;expected_x<=0;expected_y<=0;
      source_finished<=0;paint_finished<=0;rx_crc<=32'hffffffff;tx_crc<=32'hffffffff;
    end else begin
      done<=0;
      if(push)begin
        queue[wp]<=source_pixel;wp<=wp+1'b1;received<=received+1'b1;
        rx_crc<=crc_byte(rx_crc,source_pixel);
        if(expected_x==frame_w-1)begin expected_x<=0;expected_y<=expected_y+1'b1;end else expected_x<=expected_x+1'b1;
      end
      if(pop)begin rp<=rp+1'b1;painted<=painted+1'b1;tx_crc<=crc_byte(tx_crc,head);end
      case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:begin end endcase
      if(frame_active && source_done)source_finished<=1;
      if(state==FRAME && paint_done)paint_finished<=1;
      case(state)
        WAIT_INIT:if(initialized)state<=BEGIN_CLEAR;
        BEGIN_CLEAR:if(paint_ready)state<=CLEAR;
        CLEAR:if(paint_done)begin background_done<=1;state<=IDLE;end
        // Geometry changes are prepared while no source frame owns the sink.
        // Withdraw ready before clearing so the camera/core cannot send pixels.
        IDLE:if(active_crop!=crop_edge)begin
          active_crop<=crop_edge;state<=BEGIN_CLEAR;
        end else if(start)begin
          active_crop<=crop_edge;state<=BEGIN_FRAME;wp<=0;rp<=0;used<=0;received<=0;painted<=0;
          expected_x<=0;expected_y<=0;source_finished<=0;paint_finished<=0;
          rx_crc<=32'hffffffff;tx_crc<=32'hffffffff;
        end
        BEGIN_FRAME:if(paint_ready)state<=FRAME;
        FRAME:if((paint_finished || paint_done) && source_finished)begin
          if(received!=frame_pixels || painted!=frame_pixels || used!=0 || rx_crc!=tx_crc)begin error<=8'h15;state<=FAULT;end
          else begin state<=IDLE;done<=1;frames<=frames+1'b1;end
        end
        default:begin end
      endcase
      if(paint_error)begin error<=8'h14;state<=FAULT;end
      if(frame_active)begin
        if(source_error)begin error<=8'h20;state<=FAULT;end
        else if(source_valid && received>=frame_pixels)begin error<=8'h12;state<=FAULT;end
        else if(source_valid && !coordinates_ok)begin error<=8'h11;state<=FAULT;end
        else if(source_valid && used==DEPTH && !pop)begin error<=8'h10;state<=FAULT;end
        else if(source_done && received+(push?1:0)!=frame_pixels)begin error<=8'h13;state<=FAULT;end
      end
    end
  end
endmodule
