`timescale 1ns/1ps
// Rectangular RGB565 writer. Its ready/valid source is a display-side consumer,
// never the unbuffered numerical core. All CASET/RASET parameters are zero-
// extended byte fields as required by NT35510, including coordinates >255.
module nt35510_window_writer #(parameter integer PANEL_W=800,PANEL_H=480)(
  input wire clk,rst,start_valid,output wire start_ready,
  input wire [15:0] x_start,x_end,y_start,y_end,
  input wire pixel_valid,input wire [15:0] pixel_rgb565,output wire pixel_ready,
  output reg word_valid,output reg [15:0] word,output reg word_rs,
  input wire word_ready,word_done,output wire busy,
  output reg done,error,output reg [31:0] pixels_accepted
);
  localparam IDLE=0,ISSUE_SETUP=1,WAIT_SETUP=2,PIXELS=3,WAIT_LAST=4;
  reg [2:0] state;reg [4:0] setup_index;
  reg [15:0] xs,xe,ys,ye;reg [31:0] total_pixels;
  reg [15:0] command;reg [7:0] parameter_byte;
  assign start_ready=state==IDLE && !rst;
  assign busy=state!=IDLE;
  assign pixel_ready=state==PIXELS && word_ready && !rst;
  initial if(PANEL_W<1 || PANEL_W>800 || PANEL_H<1 || PANEL_H>480)
    $fatal(1,"illegal NT35510 landscape geometry");
  always @*begin
    command=16'h2a00;parameter_byte=0;
    case(setup_index[4:1])
      0:begin command=16'h2a00;parameter_byte=xs[15:8];end
      1:begin command=16'h2a01;parameter_byte=xs[7:0];end
      2:begin command=16'h2a02;parameter_byte=xe[15:8];end
      3:begin command=16'h2a03;parameter_byte=xe[7:0];end
      4:begin command=16'h2b00;parameter_byte=ys[15:8];end
      5:begin command=16'h2b01;parameter_byte=ys[7:0];end
      6:begin command=16'h2b02;parameter_byte=ye[15:8];end
      7:begin command=16'h2b03;parameter_byte=ye[7:0];end
      default:begin command=16'h2c00;parameter_byte=0;end
    endcase
    word_valid=0;word=0;word_rs=0;
    if(!rst && state==ISSUE_SETUP)begin
      word_valid=1;word_rs=setup_index[0];
      word=setup_index[0]?{8'd0,parameter_byte}:command;
    end else if(!rst && state==PIXELS)begin
      word_valid=pixel_valid;word=pixel_rgb565;word_rs=1;
    end
  end
  always @(posedge clk or posedge rst)begin
    if(rst)begin
      state<=IDLE;setup_index<=0;xs<=0;xe<=0;ys<=0;ye<=0;
      total_pixels<=0;pixels_accepted<=0;done<=0;error<=0;
    end else begin
      done<=0;error<=0;
      case(state)
        IDLE:if(start_valid)begin
          if(x_start>x_end || y_start>y_end || x_end>=PANEL_W || y_end>=PANEL_H)error<=1;
          else begin
            xs<=x_start;xe<=x_end;ys<=y_start;ye<=y_end;pixels_accepted<=0;setup_index<=0;
            total_pixels<=({16'd0,x_end}-{16'd0,x_start}+1)*({16'd0,y_end}-{16'd0,y_start}+1);
            state<=ISSUE_SETUP;
          end
        end
        ISSUE_SETUP:if(word_ready)state<=WAIT_SETUP;
        WAIT_SETUP:if(word_done)begin
          if(setup_index==16)state<=PIXELS;
          else begin setup_index<=setup_index+1'b1;state<=ISSUE_SETUP;end
        end
        PIXELS:if(pixel_valid && word_ready)begin
          pixels_accepted<=pixels_accepted+1'b1;
          if(pixels_accepted==total_pixels-1)state<=WAIT_LAST;
        end
        WAIT_LAST:if(word_done)begin state<=IDLE;done<=1;end
        default:state<=IDLE;
      endcase
    end
  end
endmodule
