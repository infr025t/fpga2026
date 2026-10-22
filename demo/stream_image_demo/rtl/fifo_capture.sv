`timescale 1ns/1ps
// OV7670 + AL422B module adapter. Module MUST gate writes with HREF.
// Configure negative VSYNC and connect module WRST# to its VSYNC.
// RCLK is free-running at 2 MHz by default, including between frames.
module fifo_capture #(
  parameter integer W=320,H=240, READ_PERIOD=50,
  parameter integer FLUSH_CYCLES=10000,TIMEOUT_CYCLES=100000000,
  parameter integer Y_BYTE=1
)(
  input wire clk,rst,start,cam_vsync,input wire [7:0]cam_data,
  output reg cam_rclk,output reg cam_rrst_n,cam_wen,
  output reg frame_start,pixel_valid,output reg[7:0]pixel,
  output reg done,output wire busy,output reg error
);
  localparam IDLE=0,WAIT_BLANK=1,WAIT_FRAME=2,CAPTURE=3,FLUSH=4,RESET_READ=5,READ=6;
  reg[2:0] state;
  reg[31:0] timer;
  reg[7:0] phase;
  reg[2:0] reset_count;
  reg[18:0] byte_count;
  (* ASYNC_REG="TRUE" *) reg[1:0]vs_sync;
  assign busy=(state!=IDLE);
  always @(posedge clk) begin
    if(rst) begin
      vs_sync<=2'b11;phase<=0;cam_rclk<=0;state<=IDLE;timer<=0;
      reset_count<=0;byte_count<=0;cam_rrst_n<=1;cam_wen<=0;
      frame_start<=0;pixel_valid<=0;pixel<=0;done<=0;error<=0;
    end else begin
      vs_sync<={vs_sync[0],cam_vsync};
      phase<=(phase==READ_PERIOD-1)?0:phase+1'b1;
      if(phase==READ_PERIOD/2-1)cam_rclk<=1;
      if(phase==READ_PERIOD-1)cam_rclk<=0;
      frame_start<=0;pixel_valid<=0;done<=0;
      if(state>=WAIT_BLANK && state<=CAPTURE) begin
        timer<=timer+1;
        if(timer==TIMEOUT_CYCLES-1) begin
          state<=IDLE;cam_wen<=0;error<=1;
        end else case(state)
          WAIT_BLANK: if(!vs_sync[1])state<=WAIT_FRAME;
          WAIT_FRAME: if(vs_sync[1])begin state<=CAPTURE;cam_wen<=1;end
          CAPTURE: if(!vs_sync[1])begin state<=FLUSH;cam_wen<=0;timer<=0;end
        endcase
      end else case(state)
        IDLE: if(start)begin state<=WAIT_BLANK;timer<=0;error<=0;end
        FLUSH: if(timer==FLUSH_CYCLES-1)begin
          if(phase==0)begin state<=RESET_READ;cam_rrst_n<=0;reset_count<=0;end
        end else timer<=timer+1;
        RESET_READ: if(phase==0)begin
          if(reset_count==4)begin
            cam_rrst_n<=1;state<=READ;byte_count<=0;frame_start<=1;
          end else reset_count<=reset_count+1'b1;
        end
        READ: if(phase==READ_PERIOD-5)begin
          // Data has settled for ~200 ns since RCLK rising edge.
          if(byte_count[0]==Y_BYTE)begin pixel<=cam_data;pixel_valid<=1;end
          if(byte_count==W*H*2-1)begin done<=1;state<=IDLE;end
          else byte_count<=byte_count+1'b1;
        end
        default: state<=IDLE;
      endcase
    end
  end
endmodule
