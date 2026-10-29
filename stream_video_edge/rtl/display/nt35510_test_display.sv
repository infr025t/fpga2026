`timescale 1ns/1ps
// Screen bring-up only: independently paced by the LCD word bus, no frame RAM.
// Clear the entire panel once, then update every active pixel without redrawing
// the static black margins. This is not an adapter for a 100 Mpixel/s core.
module nt35510_test_display #(
  parameter integer PANEL_W=800,PANEL_H=480,CORE_W=630,CORE_H=470,CORE_BORDER=5,
  parameter integer CLK_HZ=100000000,RESET_LOW_MS=20,RESET_WAIT_MS=120,SLEEP_WAIT_MS=120
)(
  input wire clk,rst,enable,input wire [1:0] pattern_select,
  output wire [7:0] lcd_data,output wire lcd_cs_n,lcd_rs,lcd_wr_n,lcd_rd_n,lcd_reset_n,lcd_bl,
  output wire initialized,output reg background_done,output reg frame_done,
  output reg [31:0] rendered_frames,output wire busy,output wire error
);
  localparam integer LEFT=(PANEL_W-CORE_W)/2,TOP=(PANEL_H-CORE_H)/2;
  localparam WAIT_INIT=0,START_BLACK=1,BLACK=2,START_IMAGE=3,IMAGE=4;
  reg [2:0] state;reg [1:0] pattern;
  reg [15:0] px,py;
  wire init_valid,init_rs,init_reset,word_ready,word_done;
  wire [15:0] init_word,paint_word;
  wire paint_valid,paint_rs,paint_ready,paint_done,paint_error,paint_busy;
  wire pixel_ready;
  wire start_valid=(state==START_BLACK || (state==START_IMAGE && enable)) && !rst;
  wire first_black=state==START_BLACK || state==BLACK;
  wire [15:0] x0=first_black?0:LEFT,x1=first_black?PANEL_W-1:LEFT+CORE_W-1;
  wire [15:0] y0=first_black?0:TOP,y1=first_black?PANEL_H-1:TOP+CORE_H-1;
  wire [15:0] source_x=px+CORE_BORDER,source_y=py+CORE_BORDER;
  reg [7:0] gray;
  always @*case(pattern)
    0:gray=source_x+source_y+rendered_frames;
    1:gray=(((source_x/16)+(source_y/16))%2==0)?32:224;
    2:gray=(2*source_x<CORE_W+2*CORE_BORDER)?32:224;
    default:gray=128;
  endcase
  wire [15:0] rgb565=first_black?16'd0:{gray[7:3],gray[7:2],gray[7:3]};
  wire pixel_valid=(state==BLACK || state==IMAGE) && !rst;
  assign lcd_bl=background_done && initialized && !rst;
  assign lcd_reset_n=init_reset && !rst;
  assign busy=!initialized || paint_busy || state==START_BLACK;
  assign error=paint_error;
  nt35510_init #(CLK_HZ,RESET_LOW_MS,RESET_WAIT_MS,SLEEP_WAIT_MS) initialize(
    .clk(clk),.rst(rst),.word_ready(word_ready && !initialized),.word_done(word_done),
    .word_valid(init_valid),.word(init_word),.word_rs(init_rs),
    .lcd_reset_n(init_reset),.init_done(initialized));
  nt35510_window_writer #(PANEL_W,PANEL_H) painter(
    .clk(clk),.rst(rst || !initialized),.start_valid(start_valid),.start_ready(paint_ready),
    .x_start(x0),.x_end(x1),.y_start(y0),.y_end(y1),
    .pixel_valid(pixel_valid),.pixel_rgb565(rgb565),.pixel_ready(pixel_ready),
    .word_valid(paint_valid),.word(paint_word),.word_rs(paint_rs),
    .word_ready(word_ready && initialized),.word_done(word_done),.busy(paint_busy),
    .done(paint_done),.error(paint_error),.pixels_accepted());
  nt35510_bus8 bus(.clk(clk),.rst(rst),
    .in_valid(initialized?paint_valid:init_valid),.in_word(initialized?paint_word:init_word),
    .in_rs(initialized?paint_rs:init_rs),.in_ready(word_ready),
    .lcd_data(lcd_data),.lcd_cs_n(lcd_cs_n),.lcd_rs(lcd_rs),.lcd_wr_n(lcd_wr_n),
    .lcd_rd_n(lcd_rd_n),.word_done(word_done));
  initial if(CORE_W<1 || CORE_H<1 || CORE_W+2*CORE_BORDER>PANEL_W || CORE_H+2*CORE_BORDER>PANEL_H ||
             CORE_BORDER<0 || CORE_W>632 || CORE_H>472)
    $fatal(1,"illegal full-resolution test canvas");
  always @(posedge clk or posedge rst)begin
    if(rst)begin state<=WAIT_INIT;pattern<=0;px<=0;py<=0;background_done<=0;frame_done<=0;rendered_frames<=0;end
    else begin
      frame_done<=0;
      case(state)
        WAIT_INIT:if(initialized)state<=START_BLACK;
        START_BLACK:if(paint_ready)state<=BLACK;
        BLACK:if(paint_done)begin background_done<=1;state<=START_IMAGE;end
        START_IMAGE:if(enable && paint_ready)begin pattern<=pattern_select;px<=0;py<=0;state<=IMAGE;end
        IMAGE:begin
          if(pixel_valid && pixel_ready)begin
            if(px==CORE_W-1)begin px<=0;py<=py+1'b1;end else px<=px+1'b1;
          end
          if(paint_done)begin
            frame_done<=1;if(rendered_frames!=32'hffffffff)rendered_frames<=rendered_frames+1'b1;
            state<=START_IMAGE;
          end
        end
        default:state<=WAIT_INIT;
      endcase
    end
  end
endmodule
