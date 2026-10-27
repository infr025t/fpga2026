`timescale 1ns/1ps
// Portable synchronous runtime. Physical camera/display and UART are separate.
module video_runtime #(
  parameter integer W=640,H=480,EXTRA_ALIGN=0,CLK_HZ=100000000,DEPTH=1024
)(
  input wire clk,rst,source_valid,input wire [63:0] source_token,
  input wire source_end_valid,input video_runtime_pkg::source_end_t source_end,
  input video_runtime_pkg::frame_config_t shadow_config,input wire stop_request,
  input wire claim,output wire latest_valid,output video_runtime_pkg::core_report_t latest,
  output wire claimed_valid,output video_runtime_pkg::core_report_t claimed_report,
  output wire source_ready,core_abort,frame_start_valid,frame_success_valid,frame_invalid_valid,
  output wire [31:0] frame_start_id,frame_success_id,frame_invalid_id,
  output wire [3:0] frame_invalid_reason,
  output wire [7:0] out_pixel,out_raw,out_base,output wire out_valid,
  output wire [9:0] out_x,output wire [8:0] out_y,
  output wire out_sof,out_eol,out_eof,output wire [31:0] out_frame_id,
  output wire [31:0] seen_frames,accepted_frames,completed_frames,invalid_frames,dropped_source,
  output wire [31:0] overflow_count,cfg_error,overwrite_count,
  output wire [10:0] fifo_highwater,fifo_level,
  output wire almost_full_seen,output wire [8:0] sticky_errors,output wire [3:0] last_reason
);
  localparam integer L_CORE=core_latency_pkg::L_CORE+EXTRA_ALIGN;
  wire iv,sof,eol,eof,arithmetic_error,done_valid,done_ok;
  wire [7:0] pixel;wire [9:0] x;wire [8:0] y;wire [31:0] fid,done_id;
  video_runtime_pkg::frame_config_t config_active;
  ingress_guard #(W,H,L_CORE,CLK_HZ,DEPTH) guard(
    .clk(clk),.rst(rst),.source_valid(source_valid),.source_token(source_token),
    .source_end_valid(source_end_valid),.source_end(source_end),.shadow_config(shadow_config),
    .stop_request(stop_request),.arithmetic_error(arithmetic_error),
    .core_done_valid(done_valid),.core_done_frame_id(done_id),.core_done_ok(done_ok),
    .core_valid(iv),.core_pixel(pixel),.core_x(x),.core_y(y),.core_sof(sof),.core_eol(eol),.core_eof(eof),
    .core_frame_id(fid),.core_abort(core_abort),.active_config(config_active),
    .frame_start_valid(frame_start_valid),.frame_start_id(frame_start_id),
    .frame_success_valid(frame_success_valid),.frame_success_id(frame_success_id),
    .frame_invalid_valid(frame_invalid_valid),.frame_invalid_id(frame_invalid_id),
    .frame_invalid_reason(frame_invalid_reason),.source_ready(source_ready),
    .seen_frames(seen_frames),.accepted_frames(accepted_frames),.completed_frames(completed_frames),
    .invalid_frames(invalid_frames),.dropped_source(dropped_source),.overflow_count(overflow_count),
    .cfg_error(cfg_error),.fifo_highwater(fifo_highwater),.fifo_level(fifo_level),
    .almost_full_seen(almost_full_seen),.sticky_errors(sticky_errors),.last_reason(last_reason));
  guided_core #(W,H,EXTRA_ALIGN) core(
    .clk(clk),.rst(rst),.abort(core_abort),.in_pixel(pixel),.in_valid(iv),
    .in_x(x),.in_y(y),.in_sof(sof),.in_eol(eol),.in_eof(eof),.in_frame_id(fid),
    .epsilon(config_active.epsilon),.threshold(config_active.threshold),.gain(config_active.gain),
    .view_mode(config_active.view_mode),.out_pixel(out_pixel),.out_raw(out_raw),.out_base(out_base),
    .out_valid(out_valid),.out_x(out_x),.out_y(out_y),.out_sof(out_sof),.out_eol(out_eol),
    .out_eof(out_eof),.out_frame_id(out_frame_id),.arithmetic_error(arithmetic_error));
  core_crc_monitor #(W,H) monitor(
    .clk(clk),.rst(rst),.abort(core_abort),.out_pixel(out_pixel),.out_raw(out_raw),.out_valid(out_valid),
    .out_x(out_x),.out_y(out_y),.out_sof(out_sof),.out_eol(out_eol),.out_eof(out_eof),.out_frame_id(out_frame_id),
    .frame_start_valid(frame_start_valid),.frame_start_id(frame_start_id),.frame_start_config(config_active),
    .frame_success_valid(frame_success_valid),.frame_success_id(frame_success_id),
    .frame_invalid_valid(frame_invalid_valid),.frame_invalid_id(frame_invalid_id),.frame_invalid_reason(frame_invalid_reason),
    .completed_frames(completed_frames),.invalid_frames(invalid_frames),.accepted_frames(accepted_frames),
    .core_done_valid(done_valid),.core_done_frame_id(done_id),.core_done_ok(done_ok),
    .latest_valid(latest_valid),.latest(latest),.claim(claim),.claimed_valid(claimed_valid),
    .claimed_report(claimed_report),.overwrite_count(overwrite_count));
endmodule
