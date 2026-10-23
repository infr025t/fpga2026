`timescale 1ns/1ps
// Standalone platform core: camera -> bounded ingress -> two-scale enhancement
// -> decimation/raw selection -> two-slot display queue. All logic is clk100.
// The eventual board wrapper must provide the display PHY/clock adapter.
module vision_top #(
  parameter integer W=320,H=240,DISPLAY_SCALE=1,INPUT_DEPTH=16,
  parameter integer CLOCK_HZ=100000000,UART_DIV=100,PATTERN_DIV=100,
  parameter integer START_DELAY=50000000,FRAME_DELAY=0,
  parameter integer CAM_RESET_CYCLES=1000000,CAM_SETTLE_CYCLES=1000000,
  parameter integer CAM_RETRY_CYCLES=100000000,CAPTURE_TIMEOUT_CYCLES=100000000,
  parameter integer PROCESS_TIMEOUT_CYCLES=20000000,CAMERA_READ_PERIOD=50,CAMERA_FLUSH_CYCLES=10000
)(input wire clk100,btnC,input wire[15:0]sw,input wire[7:0]cam_data,
  input wire cam_vsync,cam_href,inout wire cam_sioc,cam_siod,cam_rst_n,
  output wire cam_rclk,cam_rrst_n,cam_wen,uart_txd,output wire[15:0]led,
  input wire display_ready,output wire display_valid,output wire[7:0]display_pixel,
  output wire display_sof,display_eol,display_eof,output wire[31:0]display_frame_id,
  output wire display_processed,output wire[15:0]display_width,display_height,
  output reg[31:0]frame_id,processed_frames,displayed_frames,display_dropped,display_skipped,
  output reg[31:0]capture_errors,line_errors,input_overflows,processing_errors,display_errors,
  output reg[31:0]processing_fps,last_latency_cycles
);
  localparam integer DW=(W-4+DISPLAY_SCALE-1)/DISPLAY_SCALE;
  localparam integer DH=(H-4+DISPLAY_SCALE-1)/DISPLAY_SCALE;
  (* ASYNC_REG="TRUE" *) reg[1:0]button_sync=0;
  (* ASYNC_REG="TRUE" *) reg[15:0]sw_meta=0,sw_sync=0;
  reg[15:0]reset_hold=16'hffff;
  always @(posedge clk100)begin
    button_sync<={button_sync[0],btnC};reset_hold<=button_sync[1]?16'hffff:{reset_hold[14:0],1'b0};
    sw_meta<=sw;sw_sync<=sw_meta;
  end
  wire rst=|reset_hold;
  wire config_done,camera_fault,cap_sof,cap_valid,cap_done,cap_busy,cap_error,line_error;
  wire[7:0]cap_pixel;wire[15:0]captured_lines;
  reg capture_start;
  camera_frontend #(.W(W),.H(H),.CAM_RESET_CYCLES(CAM_RESET_CYCLES),
    .CAM_SETTLE_CYCLES(CAM_SETTLE_CYCLES),.CAM_RETRY_CYCLES(CAM_RETRY_CYCLES),
    .CAPTURE_TIMEOUT_CYCLES(CAPTURE_TIMEOUT_CYCLES),.READ_PERIOD(CAMERA_READ_PERIOD),
    .FLUSH_CYCLES(CAMERA_FLUSH_CYCLES)) camera(
    clk100,rst,capture_start,cam_data,cam_vsync,cam_href,cam_sioc,cam_siod,cam_rst_n,
    cam_rclk,cam_rrst_n,cam_wen,config_done,camera_fault,cap_sof,cap_valid,cap_pixel,
    cap_done,cap_busy,cap_error,line_error,captured_lines);
  localparam WAITING=0,LAUNCH=1,ARM=2,CAMERA=3,PATTERN=4,DRAIN=5;
  reg[2:0]state;
  reg[31:0]delay_count,pattern_timer,second_timer,fps_count,latency_count;
  reg pattern_selected,view_processed,pattern_active,pattern_sof,pattern_valid,got_frame;
  reg[7:0]pattern_pixel,fine_gain,coarse_gain,detail_limit;
  reg[15:0]px,py;
  reg[1:0]display_rate;reg[2:0]display_phase;reg show_frame,processing_active,abort_frame;
  wire source_sof=pattern_selected?pattern_sof:((state==CAMERA)?cap_sof:1'b0);
  wire source_valid=pattern_selected?pattern_valid:((state==CAMERA)?cap_valid:1'b0);
  wire[7:0]source_pixel=pattern_selected?pattern_pixel:cap_pixel;
  wire ingress_ready,ingress_valid,ingress_overflow;wire[8:0]ingress_data;
  wire[$clog2(INPUT_DEPTH+1)-1:0]ingress_level;
  pixel_fifo #(.WIDTH(9),.DEPTH(INPUT_DEPTH)) ingress(clk100,rst||abort_frame,
    source_sof||source_valid,{source_sof,source_pixel},ingress_ready,
    ingress_valid,ingress_data,1'b1,ingress_overflow,ingress_level);
  wire process_start=ingress_valid && ingress_data[8];
  wire core_valid,core_sof,core_eol,core_eof;
  wire[7:0]core_raw,core_fine,core_coarse,core_enhanced;
  wire[15:0]core_x,core_y;
  enhance_core #(.W(W),.H(H)) enhance(clk100,rst||abort_frame,process_start,
    ingress_valid && !ingress_data[8],ingress_data[7:0],fine_gain,coarse_gain,detail_limit,
    core_valid,core_raw,core_fine,core_coarse,core_enhanced,core_x,core_y,core_sof,core_eol,core_eof);
  wire sample=core_valid && ((core_x-2)%DISPLAY_SCALE)==0 && ((core_y-2)%DISPLAY_SCALE)==0;
  wire last_sample=sample && core_x==2+(DW-1)*DISPLAY_SCALE && core_y==2+(DH-1)*DISPLAY_SCALE;
  wire[7:0]selected_pixel=view_processed?core_enhanced:core_raw;
  reg[7:0]pending_last_pixel;
  // Hold a decimated final pixel until the COMPLETE processing frame passes.
  // This prevents an early display commit before unsampled input tail pixels.
  always @(posedge clk100)if(last_sample)pending_last_pixel<=selected_pixel;
  wire queue_valid=show_frame && ((sample && !last_sample)||core_eof);
  wire[7:0]queue_pixel=core_eof?((last_sample)?selected_pixel:pending_last_pixel):selected_pixel;
  wire queue_dropped,queue_error,frame_delivered;wire[1:0]queue_level;
  display_frame_queue #(.W(DW),.H(DH)) display_queue(clk100,rst,
    process_start && show_frame,abort_frame,frame_id,view_processed,
    queue_valid,queue_pixel,core_eof,queue_dropped,queue_error,queue_level,
    display_valid,display_ready,display_pixel,display_frame_id,display_processed,
    display_sof,display_eol,display_eof,frame_delivered);
  assign display_width=DW;assign display_height=DH;
  wire second_tick=second_timer==CLOCK_HZ-1;
  wire status_busy;
  wire[383:0]status_snapshot={last_latency_cycles,processing_fps,display_errors,processing_errors,
    input_overflows,line_errors,capture_errors,display_skipped,display_dropped,
    displayed_frames,processed_frames,frame_id};
  vision_status_tx #(.CLKS_PER_BIT(UART_DIV)) debug_status(clk100,rst,
    second_tick && sw_sync[10],{4'b0,pattern_selected,sw_sync[15],camera_fault,config_done},
    status_snapshot,uart_txd,status_busy);
  assign led=sw_sync[14]?{captured_lines[7:0],queue_level,ingress_overflow,queue_error,
    camera_fault,cap_error,config_done,!rst}:
    {camera_fault||cap_error||(processing_errors!=0),frame_id[7:0],second_timer[25],
     view_processed,pattern_selected,status_busy,cap_busy,config_done,!rst};
  always @(posedge clk100)begin
    if(rst)begin
      state<=WAITING;delay_count<=0;capture_start<=0;frame_id<=0;
      pattern_selected<=1;view_processed<=1;pattern_active<=0;pattern_sof<=0;pattern_valid<=0;
      pattern_pixel<=0;pattern_timer<=0;px<=0;py<=0;fine_gain<=24;coarse_gain<=16;detail_limit<=32;
      display_rate<=0;display_phase<=0;show_frame<=1;got_frame<=0;processing_active<=0;abort_frame<=0;
      second_timer<=0;fps_count<=0;latency_count<=0;processing_fps<=0;last_latency_cycles<=0;
      processed_frames<=0;displayed_frames<=0;display_dropped<=0;display_skipped<=0;
      capture_errors<=0;line_errors<=0;input_overflows<=0;processing_errors<=0;display_errors<=0;
    end else begin
      capture_start<=0;pattern_sof<=0;pattern_valid<=0;abort_frame<=0;
      second_timer<=second_tick?0:second_timer+1'b1;
      if(second_tick)begin processing_fps<=fps_count+(core_eof?1:0);fps_count<=0;end
      else if(core_eof)fps_count<=fps_count+1'b1;
      if(process_start)begin processing_active<=1;latency_count<=0;end
      else if(processing_active)latency_count<=latency_count+1'b1;
      if(frame_delivered)displayed_frames<=displayed_frames+1'b1;
      if(queue_dropped)display_dropped<=display_dropped+1'b1;
      if(queue_error)display_errors<=display_errors+1'b1;
      if(line_error)line_errors<=line_errors+1'b1;
      if(pattern_active)begin
        if(pattern_timer==PATTERN_DIV-1)begin
          pattern_timer<=0;pattern_valid<=1;
          pattern_pixel<=(px>=W/2)?(180+((px+py+frame_id)%16)):(40+((px*7+py*3+frame_id)%32));
          if(px==W-1)begin px<=0;if(py==H-1)pattern_active<=0;else py<=py+1'b1;end
          else px<=px+1'b1;
        end else pattern_timer<=pattern_timer+1'b1;
      end
      case(state)
        WAITING:if(delay_count<(frame_id==0?START_DELAY:FRAME_DELAY))delay_count<=delay_count+1'b1;
          else if(!sw_sync[15] && (sw_sync[0] || (config_done && !cap_busy)))begin
            pattern_selected<=sw_sync[0];view_processed<=sw_sync[1];
            case(sw_sync[3:2])0:fine_gain<=16;1:fine_gain<=24;2:fine_gain<=32;3:fine_gain<=48;endcase
            case(sw_sync[5:4])0:coarse_gain<=16;1:coarse_gain<=20;2:coarse_gain<=24;3:coarse_gain<=32;endcase
            case(sw_sync[7:6])0:detail_limit<=16;1:detail_limit<=32;2:detail_limit<=64;3:detail_limit<=255;endcase
            display_rate<=sw_sync[9:8];
            if(display_rate!=sw_sync[9:8])display_phase<=0;
            show_frame<=(display_phase==0 || display_rate!=sw_sync[9:8]);
            frame_id<=frame_id+1'b1;got_frame<=0;state<=LAUNCH;
          end
        LAUNCH:if(pattern_selected)begin
            pattern_sof<=1;pattern_active<=1;pattern_timer<=0;px<=0;py<=0;state<=PATTERN;
          end else begin capture_start<=1;state<=ARM;end
        ARM:if(cap_busy)state<=CAMERA;
        CAMERA:begin
          if(cap_sof)got_frame<=1;
          if(cap_error)begin capture_errors<=capture_errors+1'b1;delay_count<=0;state<=WAITING;end
          else if(cap_done)begin
            if(got_frame)state<=DRAIN;
            else begin delay_count<=0;state<=WAITING;end
          end
        end
        PATTERN:if(!pattern_active)state<=DRAIN;
        DRAIN:begin end
        default:begin state<=WAITING;delay_count<=0;end
      endcase
      if(core_eof)begin
        processed_frames<=processed_frames+1'b1;last_latency_cycles<=latency_count+1'b1;
        processing_active<=0;delay_count<=0;state<=WAITING;
        if(!show_frame)display_skipped<=display_skipped+1'b1;
        if(display_phase==((1<<display_rate)-1))display_phase<=0;else display_phase<=display_phase+1'b1;
      end
      if(ingress_overflow || (processing_active && !core_eof && latency_count==PROCESS_TIMEOUT_CYCLES-1))begin
        if(ingress_overflow)input_overflows<=input_overflows+1'b1;
        else processing_errors<=processing_errors+1'b1;
        abort_frame<=1;processing_active<=0;pattern_active<=0;got_frame<=0;
        delay_count<=0;state<=WAITING;
      end
    end
  end
endmodule
