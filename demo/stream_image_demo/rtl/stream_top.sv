`timescale 1ns/1ps
module stream_top #(
  parameter integer W=320,H=240,UART_DIV=100,START_DELAY=50000000,
  parameter integer CAM_RESET_CYCLES=1000000,CAM_SETTLE_CYCLES=1000000,
  parameter [15:0] ROI_X_MIN=1,ROI_Y_MIN=1,ROI_X_MAX=W-2,ROI_Y_MAX=H-2,
  parameter [31:0] TARGET_MIN_AREA=16,TARGET_MAX_AREA=((W-2)*(H-2))/2,
  parameter integer FRAME_DELAY=START_DELAY,FAST_FRAME_DELAY=0,
  parameter integer CAM_RETRY_CYCLES=100000000,CAPTURE_TIMEOUT_CYCLES=100000000,
  parameter integer PREVIEW_INTERVAL=16
)(input wire clk100,btnC,input wire[15:0]sw,input wire[7:0]cam_data,
  input wire cam_vsync,cam_href,inout wire cam_sioc,cam_siod,cam_rst_n,
  output wire cam_rclk,cam_rrst_n,cam_wen,uart_txd,output wire[15:0]led);
  (* ASYNC_REG="TRUE" *) reg[1:0]button_sync=0;
  reg[15:0]reset_hold=16'hffff;
  (* ASYNC_REG="TRUE" *) reg[15:0]sw_meta=0,sw_sync=0;
  always @(posedge clk100)begin
    button_sync<={button_sync[0],btnC};
    reset_hold<=button_sync[1]?16'hffff:{reset_hold[14:0],1'b0};
    sw_meta<=sw;sw_sync<=sw_meta;
  end
  wire rst=|reset_hold;
  // Open-drain camera reset: only drive low; the module IO-rail pullup
  // supplies the high level. Hold 10 ms, release and settle 10 ms at 100 MHz.
  localparam integer RESET_END=CAM_RESET_CYCLES+CAM_SETTLE_CYCLES;
  wire config_done,config_error;
  reg[$clog2(RESET_END+1)-1:0]camera_reset_count=0;
  reg[31:0]camera_retry_count=0;
  reg camera_fault=0;
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
  reg capture_start;
  wire cap_sof,cap_valid,cap_done,cap_busy,cap_error;
  wire[7:0]cap_pixel;
  fifo_capture #(.W(W),.H(H),.TIMEOUT_CYCLES(CAPTURE_TIMEOUT_CYCLES)) capture_camera(
    clk100,rst,capture_start,cam_vsync,cam_data,cam_rclk,cam_rrst_n,cam_wen,
    cap_sof,cap_valid,cap_pixel,cap_done,cap_busy,cap_error);
  reg pattern_mode,edge_mode;
  reg[10:0]threshold;
  reg target_enable,target_dark;
  reg[7:0]target_threshold;
  reg packed_mode,features_only,fast_frames,startup_complete;
  // In results-only mode SW13 requests one fresh image per N sent packets.
  // Zero disables previews; one sends an image every time. Failed captures
  // and pauses do not consume a slot because only tx_done advances the count.
  localparam integer PREVIEW_COUNT_WIDTH=(PREVIEW_INTERVAL>1)?$clog2(PREVIEW_INTERVAL):1;
  reg preview_active;
  reg[PREVIEW_COUNT_WIDTH-1:0]preview_count;
  wire[10:0]requested_threshold=(sw_sync[7:4]==0)?11'd160:{1'b0,sw_sync[7:4],6'b0};
  wire requested_features=!sw_sync[14] && sw_sync[11] && sw_sync[2];
  wire preview_requested=(PREVIEW_INTERVAL>0) && requested_features && sw_sync[13];
  // Re-entering or changing the source/image interpretation starts with a
  // fresh image. Reset before acquisition so a timeout retries that preview.
  wire preview_refresh=preview_requested && (!preview_active ||
    pattern_mode!=sw_sync[0] || edge_mode!=sw_sync[1] ||
    (sw_sync[0] && target_dark!=!sw_sync[3]) ||
    (sw_sync[1] && threshold!=requested_threshold));
  wire preview_due=preview_requested && (preview_refresh || preview_count==0);
  wire selected_features_only=requested_features && !preview_due;
  reg pattern_sof,pattern_valid;
  reg[7:0]pattern_pixel;
  reg[8:0]px,py;
  reg[6:0]pixel_timer;
  reg pattern_active;
  wire core_valid,core_done;
  wire[7:0]core_pixel;
  wire[16:0]core_addr;
  wire[31:0]bright_count,sum_x,sum_y;
  wire source_sof=pattern_mode?pattern_sof:cap_sof;
  wire source_valid=pattern_mode?pattern_valid:cap_valid;
  wire[7:0]source_pixel=pattern_mode?pattern_pixel:cap_pixel;
  image_core #(.W(W),.H(H)) process_image(
    clk100,rst,source_sof,edge_mode,threshold,source_valid,source_pixel,
    core_valid,core_pixel,core_addr,core_done,bright_count,sum_x,sum_y);
  wire target_done,target_config_valid,target_valid;
  wire[31:0]target_area,target_sum_x,target_sum_y;
  wire[15:0]bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max;
  target_stats #(.W(W),.H(H)) locate_target(
    .clk(clk100),.rst(rst || !target_enable),.frame_start(source_sof),
    .in_valid(source_valid),.in_pixel(source_pixel),
    .target_dark(target_dark),.target_threshold(target_threshold),
    .roi_x_min(ROI_X_MIN),.roi_y_min(ROI_Y_MIN),.roi_x_max(ROI_X_MAX),.roi_y_max(ROI_Y_MAX),
    .min_area(TARGET_MIN_AREA),.max_area(TARGET_MAX_AREA),
    .done(target_done),.config_valid(target_config_valid),.target_valid(target_valid),
    .target_area(target_area),.target_sum_x(target_sum_x),.target_sum_y(target_sum_y),
    .bbox_x_min(bbox_x_min),.bbox_y_min(bbox_y_min),.bbox_x_max(bbox_x_max),.bbox_y_max(bbox_y_max));
  // Output framebuffer decouples continuous FIFO reads from slower UART.
  // It is intentionally NOT a resettable register array.
  (* ram_style="block" *) reg[7:0]framebuffer[0:(W-2)*(H-2)-1];
  wire[16:0]read_addr;
  reg[7:0]read_data;
  wire framebuffer_write=core_valid && !features_only;
  wire framebuffer_read=!features_only;
  always @(posedge clk100)begin
    if(framebuffer_write)framebuffer[core_addr]<=core_pixel;
    if(framebuffer_read)read_data<=framebuffer[read_addr];
  end
  reg tx_start;
  wire tx_busy,tx_done;
  reg[31:0]frame_id;
  frame_sender #(.W(W-2),.H(H-2),.CLKS_PER_BIT(UART_DIV),.TARGET_PROTOCOL(1),.OUTPUT_PROTOCOL(1)) send_image(
    .clk(clk100),.rst(rst),.start(tx_start),.edge_mode(edge_mode),.threshold(threshold),
    .frame_id(frame_id),.bright_count(bright_count),.sum_x(sum_x),.sum_y(sum_y),
    .ram_addr(read_addr),.ram_data(read_data),.busy(tx_busy),.done(tx_done),.uart_txd(uart_txd),
    .target_enable(target_enable),.target_valid(target_valid),.target_dark(target_dark),
    .config_valid(target_config_valid),.target_threshold(target_threshold),
    .roi_x_min(ROI_X_MIN),.roi_y_min(ROI_Y_MIN),.roi_x_max(ROI_X_MAX),.roi_y_max(ROI_Y_MAX),
    .bbox_x_min(bbox_x_min),.bbox_y_min(bbox_y_min),.bbox_x_max(bbox_x_max),.bbox_y_max(bbox_y_max),
    .target_area(target_area),.target_sum_x(target_sum_x),.target_sum_y(target_sum_y),
    .min_area(TARGET_MIN_AREA),.max_area(TARGET_MAX_AREA),
    .pack_edges(packed_mode),.features_only(features_only));
  localparam WAITING=0,LAUNCH=1,ARM=2,PROCESSING=3,SENDING=4;
  reg[2:0]state;
  reg[31:0]delay_count;
  reg[26:0]heartbeat;
  reg core_complete,target_complete;
  wire[31:0]frame_wait_cycles=!startup_complete?START_DELAY:
    (fast_frames?FAST_FRAME_DELAY:FRAME_DELAY);
  always @(posedge clk100)begin
    if(rst)begin
      state<=WAITING;delay_count<=0;heartbeat<=0;frame_id<=0;
      pattern_mode<=1;edge_mode<=0;threshold<=160;
      target_enable<=0;target_dark<=1;target_threshold<=96;
      packed_mode<=0;features_only<=0;fast_frames<=0;startup_complete<=0;
      preview_active<=0;preview_count<=0;
      core_complete<=0;target_complete<=0;
      capture_start<=0;tx_start<=0;pattern_sof<=0;pattern_valid<=0;
      px<=0;py<=0;pixel_timer<=0;pattern_pixel<=0;pattern_active<=0;
    end else begin
      heartbeat<=heartbeat+1'b1;
      capture_start<=0;tx_start<=0;pattern_sof<=0;pattern_valid<=0;
      if(core_done)core_complete<=1;
      if(target_done)target_complete<=1;
      if(pattern_active)begin
        if(pixel_timer==99)begin
          pixel_timer<=0;pattern_valid<=1;
          if(target_enable)
            pattern_pixel<=(px>=W/4 && px<W/2 && py>=H/4 && py<3*H/4)?
              (target_dark?32:220):(target_dark?220:32);
          else pattern_pixel<=(px>=W/4 && px<W/2 && py>=H/4 && py<3*H/4)?220:((px+py)%96);
          if(px==W-1)begin px<=0;if(py==H-1)pattern_active<=0;else py<=py+1'b1;end
          else px<=px+1'b1;
        end else pixel_timer<=pixel_timer+1'b1;
      end
      case(state)
        WAITING:if(delay_count<frame_wait_cycles)delay_count<=delay_count+1;
          else if(!sw_sync[15] && (sw_sync[0] || config_done))begin
            pattern_mode<=sw_sync[0];edge_mode<=sw_sync[1];
            threshold<=requested_threshold;
            target_enable<=sw_sync[2];target_dark<=!sw_sync[3];
            // SW10/11/12/13 retain diagnostic-page meanings under SW14.
            preview_active<=preview_requested;
            if(!preview_requested || preview_refresh)preview_count<=0;
            features_only<=selected_features_only;
            packed_mode<=!sw_sync[14] && sw_sync[10] && sw_sync[1] &&
              !selected_features_only;
            fast_frames<=!sw_sync[14] && sw_sync[12];
            case(sw_sync[9:8])
              2'b00:target_threshold<=96;
              2'b01:target_threshold<=64;
              2'b10:target_threshold<=128;
              2'b11:target_threshold<=160;
            endcase
            frame_id<=frame_id+1'b1;state<=LAUNCH;
          end
        LAUNCH:begin
          startup_complete<=1;
          core_complete<=0;target_complete<=0;
          if(pattern_mode)begin
            pattern_sof<=1;px<=0;py<=0;pixel_timer<=0;pattern_active<=1;state<=PROCESSING;
          end else begin capture_start<=1;state<=ARM;end
        end
        ARM:if(cap_busy)state<=PROCESSING;
        PROCESSING:if((core_done || core_complete) &&
            (!target_enable || target_done || target_complete))begin tx_start<=1;state<=SENDING;end
          else if(!pattern_mode && cap_error)begin delay_count<=0;state<=WAITING;end
        SENDING:if(tx_done)begin
          if(preview_active)begin
            if(PREVIEW_INTERVAL<=1 || preview_count==PREVIEW_INTERVAL-1)preview_count<=0;
            else preview_count<=preview_count+1'b1;
          end
          delay_count<=0;state<=WAITING;
        end
        default:state<=WAITING;
      endcase
    end
  end
  wire vs_seen,href_seen,wen_seen,overlap_seen,href_vs_high,href_vs_low;
  wire[15:0]captured_lines,high_lines,low_lines;
  camera_monitor monitor_camera(clk100,rst,config_done,cam_vsync,cam_href,cam_wen,
    vs_seen,href_seen,wen_seen,overlap_seen,captured_lines,href_vs_high,href_vs_low,high_lines,low_lines);
  // SW14 selects diagnostics and masks output-speedup switch requests.
  // In diagnostics SW13 chooses high/low line-count byte; normally it enables
  // periodic previews while SW2 and SW11 request target results.
  // Status means observed at FPGA inputs/internal WEN, not at the FIFO chip.
  // SW12 selects register readback page; SW11:10 chooses PID/COM10/TSLB/COM7.
  wire[7:0]register_byte=register_values[sw_sync[11:10]*8+:8];
  wire[15:0]diagnostic_lines=(sw_sync[11:10]==0)?captured_lines:
    (sw_sync[11:10]==1)?high_lines:(sw_sync[11:10]==2)?low_lines:16'b0;
  assign led=(sw_sync[14] && sw_sync[12])?{register_byte,!camera_config_rst,
    camera_fault,cap_error,href_vs_low,href_vs_high,read_error,read_done,config_done}:
    sw_sync[14]?{(sw_sync[13]?diagnostic_lines[15:8]:diagnostic_lines[7:0]),
    !camera_config_rst,camera_fault,cap_error,overlap_seen,wen_seen,href_seen,vs_seen,config_done}:
    {(!sw_sync[0] && (camera_fault||cap_error)),frame_id[7:0],
    heartbeat[26],edge_mode,pattern_mode,tx_busy,cap_busy,config_done,!rst};
endmodule

// Passive diagnostic observer. No connection to acquisition control.
// Kept in this source file so existing Vivado projects need no new RTL source.
module camera_monitor(input wire clk,rst,enabled,vsync,href,wen,
  output reg vs_seen,href_seen,wen_seen,overlap_seen,
  output reg[15:0]captured_lines,output reg href_vs_high,href_vs_low,
  output reg[15:0]high_lines,low_lines);
  (* ASYNC_REG="TRUE" *) reg[1:0]vs_sync=2'b11,href_sync=0;
  reg vs_prev,href_prev,wen_prev;
  reg[15:0]line_count;
  reg[15:0]high_count,low_count;
  always @(posedge clk)begin
    vs_sync<={vs_sync[0],vsync};href_sync<={href_sync[0],href};
    vs_prev<=vs_sync[1];href_prev<=href_sync[1];wen_prev<=wen;
    if(rst || !enabled)begin
      vs_seen<=0;href_seen<=0;wen_seen<=0;overlap_seen<=0;
      captured_lines<=0;line_count<=0;
      href_vs_high<=0;href_vs_low<=0;
      high_count<=0;low_count<=0;high_lines<=0;low_lines<=0;
    end else begin
      if(vs_prev!=vs_sync[1])vs_seen<=1;
      if(href_prev!=href_sync[1])href_seen<=1;
      if(wen)wen_seen<=1;
      if(wen && href_sync[1])overlap_seen<=1;
      // Sample VSYNC at each HREF rising edge, independent of WR.
      if(href_sync[1] && !href_prev)begin
        if(vs_sync[1])href_vs_high<=1;else href_vs_low<=1;
        if(vs_sync[1] && high_count!=16'hffff)high_count<=high_count+1'b1;
        if(!vs_sync[1] && low_count!=16'hffff)low_count<=low_count+1'b1;
      end
      // Latch each completed phase, independent of the capture controller.
      // A simultaneous HREF rise belongs to the newly entered VSYNC phase.
      if(vs_prev && !vs_sync[1])begin high_lines<=high_count;high_count<=0;end
      if(!vs_prev && vs_sync[1])begin low_lines<=low_count;low_count<=0;end
      // A first HREF edge can coincide with WEN becoming active.
      if(wen && !wen_prev)line_count<=(href_sync[1] && !href_prev)?16'd1:16'd0;
      else if(wen && href_sync[1] && !href_prev && line_count!=16'hffff)
        line_count<=line_count+1'b1;
      if(!wen && wen_prev)captured_lines<=line_count;
    end
  end
endmodule
