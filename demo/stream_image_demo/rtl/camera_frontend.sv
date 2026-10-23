`timescale 1ns/1ps
// Existing OV7670/AL422 adapter, with mandatory HREF line-count validation.
// The external AL422 performs the camera-clock -> clk domain frame transfer.
module camera_frontend #(
  parameter integer W=320,H=240,CAM_RESET_CYCLES=1000000,CAM_SETTLE_CYCLES=1000000,
  parameter integer CAM_RETRY_CYCLES=100000000,CAPTURE_TIMEOUT_CYCLES=100000000,
  parameter integer READ_PERIOD=50,FLUSH_CYCLES=10000,CHECK_LINES=1
)(input wire clk100,rst,start,input wire[7:0]cam_data,input wire cam_vsync,cam_href,
  inout wire cam_sioc,cam_siod,cam_rst_n,output wire cam_rclk,cam_rrst_n,cam_wen,
  output wire config_done,output reg camera_fault=0,
  output reg frame_start,pixel_valid,output reg[7:0]pixel,output reg done,
  output wire busy,error,output reg line_error,output wire[15:0]captured_lines);
  localparam integer RESET_END=CAM_RESET_CYCLES+CAM_SETTLE_CYCLES;
  wire config_error;
  reg[$clog2(RESET_END+1)-1:0]camera_reset_count=0;
  reg[31:0]camera_retry_count=0;

  always @(posedge clk100)begin
    if(rst)begin
      camera_reset_count<=0;camera_retry_count<=0;camera_fault<=0;
    end else begin
      if(config_error)camera_fault<=1;
      else if(config_done)camera_fault<=0;
      if(camera_reset_count<RESET_END)begin
        camera_reset_count<=camera_reset_count+1'b1;camera_retry_count<=0;
      end else if(config_error && CAM_RETRY_CYCLES>0)begin
        if(camera_retry_count==CAM_RETRY_CYCLES-1)begin
          camera_reset_count<=0;camera_retry_count<=0;
        end else camera_retry_count<=camera_retry_count+1'b1;
      end else camera_retry_count<=0;
    end
  end
  wire camera_reset_low=rst || (camera_reset_count<CAM_RESET_CYCLES);
  wire camera_config_rst=rst || (camera_reset_count<RESET_END);
  assign cam_rst_n=camera_reset_low?1'b0:1'bz;
  wire cfg_scl_low,cfg_sda_low,rd_scl_low,rd_sda_low;
  wire read_done,read_error;
  wire[31:0]register_values;
  // One physical open-drain driver per pin. Configuration then readback;
  // the inactive sequencer releases both lines.
  assign cam_sioc=(cfg_scl_low||rd_scl_low)?1'b0:1'bz;
  assign cam_siod=(cfg_sda_low||rd_sda_low)?1'b0:1'bz;
  camera_config #(.DIRECT_IO(0)) config_camera(clk100,camera_config_rst,cam_sioc,cam_siod,
    config_done,config_error,cfg_scl_low,cfg_sda_low);
  camera_readback #(.DIRECT_IO(0)) read_camera(clk100,camera_config_rst,config_done,
    cam_sioc,cam_siod,read_done,read_error,register_values,rd_scl_low,rd_sda_low);

  wire raw_sof,raw_valid,raw_done;wire[7:0]raw_pixel;
  fifo_capture #(.W(W),.H(H),.READ_PERIOD(READ_PERIOD),.FLUSH_CYCLES(FLUSH_CYCLES),
    .TIMEOUT_CYCLES(CAPTURE_TIMEOUT_CYCLES)) capture_camera(
    clk100,rst,start,cam_vsync,cam_data,cam_rclk,cam_rrst_n,cam_wen,
    raw_sof,raw_valid,raw_pixel,raw_done,busy,error);
  wire vs_seen,href_seen,wen_seen,overlap_seen,href_high,href_low;
  wire[15:0]high_lines,low_lines;
  camera_monitor monitor_camera(clk100,rst,config_done,cam_vsync,cam_href,cam_wen,
    vs_seen,href_seen,wen_seen,overlap_seen,captured_lines,href_high,href_low,high_lines,low_lines);
  reg valid_frame;
  always @(posedge clk100)begin
    if(rst)begin frame_start<=0;pixel_valid<=0;pixel<=0;done<=0;line_error<=0;valid_frame<=0;end
    else begin
      frame_start<=0;line_error<=0;pixel_valid<=raw_valid && valid_frame;pixel<=raw_pixel;done<=raw_done;
      if(start)valid_frame<=0;
      if(raw_sof)begin
        valid_frame<=!CHECK_LINES || captured_lines==H;
        frame_start<=!CHECK_LINES || captured_lines==H;
        line_error<=CHECK_LINES && captured_lines!=H;
      end
    end
  end
endmodule
