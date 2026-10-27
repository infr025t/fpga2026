`timescale 1ns/1ps
// One accepted frame in flight. Two elastic prefetch entries account for the
// RAM's registered read response; consumers never backpressure the source.
module ingress_guard #(
  parameter integer W=640,H=480,L_CORE=core_latency_pkg::L_CORE,
  parameter integer CLK_HZ=100000000,DEPTH=1024
)(
  input wire clk,rst,source_valid,input wire [63:0] source_token,
  input wire source_end_valid,input video_runtime_pkg::source_end_t source_end,
  input video_runtime_pkg::frame_config_t shadow_config,
  input wire stop_request,arithmetic_error,
  input wire core_done_valid,input wire [31:0] core_done_frame_id,input wire core_done_ok,
  output wire core_valid,output wire [7:0] core_pixel,
  output wire [9:0] core_x,output wire [8:0] core_y,
  output wire core_sof,core_eol,core_eof,output wire [31:0] core_frame_id,
  output reg core_abort,output video_runtime_pkg::frame_config_t active_config,
  output wire frame_start_valid,output wire [31:0] frame_start_id,
  output wire frame_success_valid,output wire [31:0] frame_success_id,
  output wire frame_invalid_valid,output wire [31:0] frame_invalid_id,
  output wire [3:0] frame_invalid_reason,output wire source_ready,
  output reg [31:0] seen_frames,accepted_frames,completed_frames,invalid_frames,dropped_source,
  output reg [31:0] overflow_count,cfg_error,
  output reg [10:0] fifo_highwater,output wire [10:0] fifo_level,
  output reg almost_full_seen,output reg [8:0] sticky_errors,output reg [3:0] last_reason
);
  import video_runtime_pkg::*;
  localparam WAIT_SOF=0,RUN=1,DRAIN=2,RECOVER=3;
  localparam integer S_FRAME=(L_CORE+64>128)?L_CORE+64:128;
  localparam integer TIMEOUT=(CLK_HZ/10<1)?1:CLK_HZ/10;
  localparam integer ALERT=(DEPTH>=896)?896:DEPTH-1;
  reg [1:0] state;
  reg [31:0] active_id,pending_starts,idle_count,handoff_count,drain_count;
  reg [9:0] expected_x;reg [8:0] expected_y;
  reg end_seen,done_seen;
  frame_config_t saved_config;
  reg [63:0] head,second;reg [1:0] prefetched;
  wire rd_valid,empty,full;wire [63:0] rd_data;
  wire [$clog2(DEPTH+1)-1:0] ram_level;
  wire busy=state==RUN || state==DRAIN;
  wire present=prefetched!=0;
  wire [31:0] head_id=head[61:30];
  wire physical_sof=source_valid && source_token[27];
  wire recovery_start=state==RECOVER && !core_abort && !stop_request && physical_sof;
  wire write_base=!rst && !core_abort && source_valid &&
    ((state!=RECOVER && !(state==WAIT_SOF && stop_request)) || recovery_start);
  wire overflow_event=write_base && full;
  wire source_ok_now=source_end_valid && source_end.frame_id==active_id && source_end.ok && source_end.reason==0;
  wire done_ok_now=core_done_valid && core_done_frame_id==active_id && core_done_ok;
  wire completion_ready=state==DRAIN && drain_count>=L_CORE &&
    (end_seen || source_ok_now) && (done_seen || done_ok_now);
  wire legal_config=(shadow_config.epsilon==16 || shadow_config.epsilon==64 ||
    shadow_config.epsilon==256 || shadow_config.epsilon==1024) && shadow_config.threshold<=16 &&
    shadow_config.gain<=512 && (shadow_config.view_mode!=2 || shadow_config.gain==256) &&
    (shadow_config.view_mode>=2 || shadow_config.gain==0);
  wire first_legal=present && head[27] && head[17:8]==0 && head[26:18]==0 &&
    !head[63] && !head[62] && !head[28] && !head[29];
  wire running_legal=!head[63] && !head[62] && head_id==active_id &&
    head[17:8]==expected_x && head[26:18]==expected_y && !head[27] &&
    head[28]==(expected_x==W-1) && head[29]==(expected_x==W-1 && expected_y==H-1);
  reg fault;reg [3:0] reason;
  always @*begin
    fault=0;reason=0;
    if(!rst && !core_abort && state!=RECOVER)begin
      if(overflow_event)begin fault=1;reason=2;end
      else if(busy && arithmetic_error)begin fault=1;reason=6;end
      else if(busy && source_end_valid &&
        (source_end.frame_id!=active_id || !source_end.ok || source_end.reason!=0 || end_seen))begin
        fault=1;reason=(!source_end.ok && source_end.reason>=1 && source_end.reason<=8)?source_end.reason:4'd3;
      end else if(busy && core_done_valid &&
        (core_done_frame_id!=active_id || !core_done_ok || state!=DRAIN || done_seen))begin
        fault=1;reason=3;
      end else if(!source_valid && (|source_token[29:27]))begin fault=1;reason=3;end
      else if(state==RUN && present && !running_legal)begin fault=1;reason=3;end
      else if(state==WAIT_SOF && present && head[27] && !first_legal)begin fault=1;reason=3;end
      else if(busy && !completion_ready && handoff_count>=S_FRAME-1)begin fault=1;reason=3;end
      else if(busy && !completion_ready && idle_count>=TIMEOUT-1)begin fault=1;reason=5;end
    end
  end
  wire idle_stop=state==WAIT_SOF && stop_request && !core_abort;
  wire flush=fault || idle_stop;
  assign frame_success_valid=completion_ready && !fault && !rst && !core_abort;
  assign frame_success_id=active_id;
  assign frame_start_valid=!rst && !core_abort && !fault && !stop_request && first_legal &&
    (state==WAIT_SOF || frame_success_valid);
  assign frame_start_id=head_id;
  // SOF bypass is required: the numerical core samples config on this same edge.
  assign active_config=(frame_start_valid && legal_config)?shadow_config:saved_config;
  assign core_valid=!rst && !core_abort && !fault &&
    ((state==RUN && present) || frame_start_valid);
  assign core_pixel=head[7:0];assign core_x=head[17:8];assign core_y=head[26:18];
  assign core_frame_id=head_id;
  assign core_sof=core_valid && head[27];assign core_eol=core_valid && head[28];
  assign core_eof=core_valid && head[29];
  assign frame_invalid_valid=fault && busy;
  assign frame_invalid_id=active_id;assign frame_invalid_reason=reason;
  assign source_ready=!rst && !core_abort && !stop_request && state!=RECOVER && !full;
  wire pop_head=core_valid || (!rst && !core_abort && !fault && state==WAIT_SOF &&
    !stop_request && present && !head[27]);
  // Reserve room for the response already in flight before issuing another read.
  wire read_request=!rst && !core_abort && !fault && !empty &&
    ({1'b0,prefetched}+rd_valid-pop_head<2);
  wire write_request=write_base && !fault;
  ingress_fifo #(DEPTH) fifo(.clk(clk),.rst(rst || core_abort),.wr_en(write_request),
    .wr_data(source_token),.rd_en(read_request),.rd_valid(rd_valid),.rd_data(rd_data),
    .empty(empty),.full(full),.level(ram_level),.overflow());
  assign fifo_level=ram_level;
  always @(posedge clk)begin
    if(rst || core_abort)prefetched<=0;
    else if(!flush)case({rd_valid,pop_head})
      2'b10:begin if(prefetched==0)head<=rd_data;else second<=rd_data;prefetched<=prefetched+1'b1;end
      2'b01:begin head<=second;prefetched<=prefetched-1'b1;end
      2'b11:begin
        if(prefetched==1)head<=rd_data;
        else begin head<=second;second<=rd_data;end
      end
      default:begin end
    endcase
  end
  initial if(W<16 || W>640 || H<16 || H>480 || L_CORE<1 || DEPTH<2 || DEPTH>1024 || TIMEOUT<=L_CORE+2)
    $fatal(1,"illegal runtime guard parameters");
  always @(posedge clk)begin
    if(rst)begin
      state<=WAIT_SOF;core_abort<=0;active_id<=0;expected_x<=0;expected_y<=0;
      end_seen<=0;done_seen<=0;pending_starts<=0;idle_count<=0;handoff_count<=0;drain_count<=0;
      seen_frames<=0;accepted_frames<=0;completed_frames<=0;invalid_frames<=0;dropped_source<=0;
      overflow_count<=0;cfg_error<=0;fifo_highwater<=0;almost_full_seen<=0;sticky_errors<=0;last_reason<=0;
      saved_config<='0;saved_config.epsilon<=1024;saved_config.threshold<=2;
      saved_config.gain<=256;saved_config.view_mode<=2;saved_config.profile_id<=1;
    end else begin
      core_abort<=flush;
      if(physical_sof)seen_frames<=sat_add(seen_frames,33'd1);
      if(frame_start_valid)accepted_frames<=sat_add(accepted_frames,33'd1);
      if(frame_success_valid)completed_frames<=sat_add(completed_frames,33'd1);
      if(frame_invalid_valid)invalid_frames<=sat_add(invalid_frames,33'd1);
      if(overflow_event)overflow_count<=sat_add(overflow_count,33'd1);
      dropped_source<=sat_add(dropped_source,
        {1'b0,(flush?pending_starts:32'd0)}+((physical_sof && !write_request)?33'd1:33'd0));
      if(flush)pending_starts<=0;
      else pending_starts<=sat_add(pending_starts,(physical_sof && write_request)?33'd1:33'd0)-
        (frame_start_valid?32'd1:32'd0);
      if(ram_level>fifo_highwater)fifo_highwater<=ram_level;
      if(ram_level>=ALERT)almost_full_seen<=1;
      if(busy && !core_valid)idle_count<=idle_count+1'b1;else idle_count<=0;
      if(busy && !frame_success_valid && pending_starts!=0)handoff_count<=handoff_count+1'b1;
      else handoff_count<=0;
      if(state==DRAIN && drain_count<L_CORE)drain_count<=drain_count+1'b1;
      if(state==RECOVER && recovery_start)state<=WAIT_SOF;
      if(busy && !frame_start_valid)begin
        if(source_ok_now)end_seen<=1;
        if(done_ok_now)done_seen<=1;
      end
      if(frame_success_valid)begin state<=WAIT_SOF;end_seen<=0;done_seen<=0;end
      if(core_valid && state==RUN)begin
        if(expected_x==W-1)begin expected_x<=0;expected_y<=expected_y+1'b1;end
        else expected_x<=expected_x+1'b1;
        if(core_eof)begin state<=DRAIN;drain_count<=0;end
      end
      if(frame_start_valid)begin
        state<=RUN;active_id<=head_id;expected_x<=1;expected_y<=0;
        end_seen<=source_end_valid && source_end.frame_id==head_id && source_end.ok && source_end.reason==0;
        done_seen<=0;drain_count<=0;idle_count<=0;handoff_count<=0;
        if(legal_config)saved_config<=shadow_config;else cfg_error<=sat_add(cfg_error,33'd1);
      end
      if(flush)begin
        state<=RECOVER;end_seen<=0;done_seen<=0;idle_count<=0;handoff_count<=0;drain_count<=0;
        if(fault)begin last_reason<=reason;sticky_errors[reason]<=1'b1;end
      end
    end
  end
endmodule
