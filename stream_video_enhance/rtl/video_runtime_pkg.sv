`timescale 1ns/1ps
package video_runtime_pkg;
  typedef struct packed {
    logic [10:0] epsilon;
    logic [4:0] threshold;
    logic [9:0] gain;
    logic [1:0] view_mode;
    logic [15:0] cfg_id, profile_id;
    logic [1:0] source_kind;
    logic [7:0] pattern_id;
    logic legacy_validation, preview_enable, roi_pair;
  } frame_config_t;
  typedef struct packed {
    logic [31:0] frame_id;
    logic ok;
    logic [3:0] reason;
  } source_end_t;
  typedef struct packed {
    logic [31:0] frame_id;
    frame_config_t frame_config;
    logic [31:0] pixel_count, raw_crc, selected_crc;
    logic [31:0] diagnostic_seq, report_overwrite_count;
    logic [31:0] completed_frames, invalid_frames, accepted_frames;
  } core_report_t;
  function automatic [31:0] sat_add(input [31:0] value, input [32:0] increment);
    reg [33:0] sum;
    begin sum={2'b0,value}+{1'b0,increment};sat_add=(|sum[33:32])?32'hffffffff:sum[31:0];end
  endfunction
  function automatic [63:0] pack_pixel(input [7:0] pixel,input [9:0] x,input [8:0] y,
    input sof,eol,eof,input [31:0] frame_id);
    pack_pixel={2'b0,frame_id,eof,eol,sof,y,x,pixel};
  endfunction
endpackage
