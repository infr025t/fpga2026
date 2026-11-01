`timescale 1ns/1ps
// 系统顶层：初始化摄像头与屏幕，按帧接纳 RAW/EDGE 请求，统一实体开关与调试控制。
module lcd_top #(parameter SENSOR_PLL=8'h8a,parameter integer STAT_FRAMES=0)(
  input wire clk100,btnC,input wire[15:0]sw,
  input wire[7:0]cam_data,input wire cam_vsync,cam_href,
  inout wire cam_sioc,cam_siod,cam_rst_n,
  output wire cam_wrst_n,cam_rclk,cam_rrst_n,cam_wen,uart_txd,
  output wire[7:0]lcd_data,output wire lcd_cs_n,lcd_rs,lcd_wr_n,lcd_rd_n,lcd_reset_n,lcd_bl,
  output wire[15:0]led
);
  wire[15:0]virtual_sw;wire[1:0]debug_control;
  wire[15:0]selected_sw=debug_control[0]?virtual_sw:sw;
  (* ASYNC_REG="TRUE" *)reg[1:0]button_sync=0;
  (* ASYNC_REG="TRUE" *)reg[15:0]sm=0,ss=0;
  reg[15:0]reset_hold=16'hffff;
  always @(posedge clk100)begin
    button_sync<={button_sync[0],btnC|debug_control[1]};
    reset_hold<=button_sync[1]?16'hffff:{reset_hold[14:0],1'b0};
    sm<=selected_sw;ss<=sm;
  end
  wire rst=reset_hold[15];
  reg[21:0]power_count=0;reg[27:0]warmup=0;reg config_scene=1;
  wire config_done,config_error,sl,dl;
  wire camera_ready=config_done && !config_error && warmup==200000000;
  assign cam_rst_n=(rst || power_count<1000000)?1'b0:1'bz;
  assign cam_sioc=sl?1'b0:1'bz;assign cam_siod=dl?1'b0:1'bz;
  ov7670_config #(.DIRECT_IO(0),.FREEZE_AEC(0),.FREEZE_AGC(0),.PLL_VALUE(SENSOR_PLL)) configure_camera(
    .clk(clk100),.rst(rst || power_count<2000000),.slow_clock(1'b0),.scene(config_scene),
    .sioc(cam_sioc),.siod(cam_siod),.done(config_done),.error(config_error),.scl_drive_low(sl),.sda_drive_low(dl));
  wire statistics_complete;
  reg ref_fault=0;reg[127:0]completed_metrics=0;
  reg start=0,inflight=0,active_internal=0,active_edge=0,frame_complete=0;
  wire sink_ready,sink_busy,sink_done,lcd_initialized,background_done;
  wire[7:0]sink_error,cap_error;wire cap_busy,cap_done,cv;wire[7:0]cp,cp_other;reg[7:0]cp_other_aligned;wire[9:0]cx;wire[8:0]cy;
  wire[255:0]debug_camera,camera_timing_live;wire[127:0]debug_sync;
  wire[7:0]observed_cap_error;
  capture_fault_latch first_fault(.clk(clk100),.rst(rst),.live_error(cap_error),.live_timing(camera_timing_live),
    .observed_error(observed_cap_error),.observed_timing(debug_camera));
  wire[10:0]debug_read_command;wire[511:0]snapshot_block;wire[31:0]snapshot_status;
  wire[31:0]sensor_frames,read_frames,sensor_period,max_occupancy;
  // 已接纳的源帧必须排空；切换模式或暂停不能撤销当拍请求，修复源端与显示端不同步。
  wire camera_admitted=start && !active_internal;
  camera_fifo_video camera(
    .clk(clk100),.rst(rst),.start(camera_admitted),
    .pause(!camera_admitted && (ss[15]||ss[0]||ref_fault||statistics_complete||(!sink_ready&&!inflight))),
    .vsync(cam_vsync),.href(cam_href),.data(cam_data),
    .rclk(cam_rclk),.rrst(cam_rrst_n),.wrst(cam_wrst_n),.wen(cam_wen),.busy(cap_busy),.done(cap_done),.error(cap_error),
    .pixel_valid(cv),.pixel(cp),.pixel_other(cp_other),.pixel_x(cx),.pixel_y(cy),.debug_timing(camera_timing_live),.debug_sync(debug_sync),
    .sensor_frames(sensor_frames),.read_frames(read_frames),.sensor_period(sensor_period),.max_occupancy(max_occupancy));
  reg pattern_busy=0,pv=0,pd=0,end_pending=0;
  reg[6:0]cooldown=0;reg[9:0]px=0,ox=0;reg[8:0]py=0,oy=0;reg[7:0]pp=0;
  always @(posedge clk100)begin
    pv<=0;pd<=0;
    if(rst)begin pattern_busy<=0;end_pending<=0;cooldown<=0;px<=0;py<=0;ox<=0;oy<=0;pp<=0;end
    else if(start)begin pattern_busy<=active_internal;end_pending<=0;cooldown<=0;px<=0;py<=0;end
    else begin
      if(end_pending)begin pd<=1;end_pending<=0;end
      if(pattern_busy)begin
        if(cooldown!=0)cooldown<=cooldown-1'b1;
        else begin
          cooldown<=11;pv<=1;pp<=(px+3*py+7)^(px>>3);ox<=px;oy<=py;
          if(px==639)begin px<=0;if(py==479)begin pattern_busy<=0;end_pending<=1;end else py<=py+1'b1;end
          else px<=px+1'b1;
        end
      end
    end
  end
  // 相邻字节与显示接口同延迟，仅供诊断；不得用其内容决定是否交换Y/UV。
  always @(posedge clk100)if(cv)cp_other_aligned<=cp_other;
  wire ov,od,core_error;wire[7:0]op,original_pixel;wire[9:0]oxp;wire[8:0]oyp;
  video_core_adapter processing(.clk(clk100),.rst(rst),.start(start),.edge_view(active_edge),
    .source_valid(active_internal?pv:cv),.source_pixel(active_internal?pp:cp),
    .source_x(active_internal?ox:cx),.source_y(active_internal?oy:cy),.source_done(active_internal?pd:cap_done),
    .out_valid(ov),.out_pixel(op),.out_raw(original_pixel),.out_x(oxp),.out_y(oyp),.out_done(od),.error(core_error));
  wire[31:0]received,painted,input_crc,output_crc,frames;
  video_lcd_sink #(.BUS_SETUP(2),.BUS_LOW(2),.BUS_HOLD(2),.BUS_GAP(0)) display(
    .clk(clk100),.rst(rst),.start(start),
     .crop_edge(start?active_edge:ss[2]),.source_valid(ov),.source_pixel(op),
    .source_x(oxp),.source_y(oyp),
    .source_done(od),.source_error((!active_internal && cap_error!=0)||core_error),
    .ready(sink_ready),.busy(sink_busy),.done(sink_done),.error(sink_error),
    .initialized(lcd_initialized),.background_done(background_done),.received(received),.painted(painted),
    .input_crc(input_crc),.output_crc(output_crc),.frames(frames),
    .lcd_data(lcd_data),.lcd_cs_n(lcd_cs_n),.lcd_rs(lcd_rs),.lcd_wr_n(lcd_wr_n),.lcd_rd_n(lcd_rd_n),
    .lcd_reset_n(lcd_reset_n),.lcd_bl(lcd_bl));
  wire[7:0]error=config_error?8'h80:ref_fault?8'h40:(observed_cap_error!=0?observed_cap_error:sink_error);
  wire ready=(ss[0] || camera_ready) && sink_ready;
  always @(posedge clk100)begin
    start<=0;
    if(rst)begin power_count<=0;warmup<=0;config_scene<=1;inflight<=0;active_internal<=0;active_edge<=0;frame_complete<=0;end
    else begin
      if(power_count<2000000)power_count<=power_count+1'b1;
      if(power_count<1000000)config_scene<=!ss[1];
      if(!config_done)warmup<=0;else if(warmup<200000000)warmup<=warmup+1'b1;
      if(!statistics_complete && !inflight && !cap_busy && !pattern_busy && ready && !ss[15] && sink_error==0 && (ss[0] || error==0))begin
        start<=1;inflight<=1;active_internal<=ss[0];active_edge<=ss[2];frame_complete<=0;
      end
      if(sink_done)begin inflight<=0;frame_complete<=1;end
    end
  end
  // 完成时锁存整帧指标；统计停止条件仅由显式 STAT_FRAMES 参数启用。
  reg[31:0]ticks=0,last_done_tick=0,last_interval=0,max_interval=0,display_frames=0,reference_failures=0;
  assign statistics_complete=STAT_FRAMES>0 && display_frames>=STAT_FRAMES;
  reg have_done=0;
  wire[31:0]interval=ticks-last_done_tick;
  wire reference_enabled=active_internal || (!config_scene&&!active_edge);
  wire[31:0]reference_crc=active_internal?(active_edge?32'h00032a9c:32'hf9824a15):32'h6df0b9b5;
  always @(posedge clk100)begin
    if(rst)begin ticks<=0;last_done_tick<=0;last_interval<=0;max_interval<=0;display_frames<=0;reference_failures<=0;
      have_done<=0;ref_fault<=0;completed_metrics<=0;end
    else begin
      ticks<=ticks+1'b1;
      if(sink_done)begin
        completed_metrics<={input_crc,output_crc,received,painted};display_frames<=display_frames+1'b1;
        last_done_tick<=ticks;have_done<=1;
        if(have_done)begin last_interval<=interval;if(interval>max_interval)max_interval<=interval;end
        if(reference_enabled && input_crc!=reference_crc)begin ref_fault<=(STAT_FRAMES==0);reference_failures<=reference_failures+1'b1;end
      end
    end
  end
  wire[255:0]debug_performance={reference_failures,max_occupancy,display_frames,read_frames,sensor_frames,sensor_period,max_interval,last_interval};
  wire[7:0]flags={ss[15],active_internal,frame_complete,sink_busy,cap_busy,background_done,lcd_initialized,ready};
  wire[31:0]debug_status={frames[15:0],error,flags};
  wire[127:0]debug_metrics=completed_metrics;
// 通用诊断：保留快照、色条比较、串口；它们不会向计算核心施加反压。
`ifdef LCD_SNAPSHOT
  wire[127:0]bars_diagnostic;wire[31:0]uart_debug_dropped,uart_debug_packets;
  uart_pair_stream uart_diagnostic(.clk(clk100),.rst(rst),.start(camera_admitted&&!active_edge),
    .source_valid(cv&&!active_internal&&!active_edge),.pixel(cp),.other(cp_other),.x(cx),.y(cy),
    .source_done(cap_done),.uart_txd(uart_txd),.dropped(uart_debug_dropped),.packets(uart_debug_packets));
  bars_monitor bars_compare(.clk(clk100),.rst(rst),.start(start),
    .enable(!config_scene&&!active_internal&&!active_edge),.pixel_valid(cv),.pixel(cp),.x(cx),.y(cy),.status(bars_diagnostic));
  video_snapshot #(.OVERVIEW(1),.ROI(1),.ROI_W(640),.ROI_H(16),.BLOCK_WORDS(32)) snapshot(.clk(clk100),.rst(rst),.start(start),
    .pixel_valid(ov),.pixel(op),.x(oxp),.y(oyp),.source_done(od),.crop_edge(active_edge),
    .raw_pixel((!active_internal&&!active_edge)?cp_other_aligned:original_pixel),.read_command(debug_read_command),
    .block_data(snapshot_block),.status(snapshot_status));
`else
  assign snapshot_block=0;assign snapshot_status=0;assign uart_txd=1;
`endif
`ifdef DIAG_JTAG
  lcd_vio debug_bridge(.clk(clk100),.probe_in0(debug_status),.probe_in1(debug_camera),.probe_in2(debug_metrics),
    `ifdef LCD_SNAPSHOT
    .probe_in3(debug_performance),.probe_in4(snapshot_block[255:0]),
    .probe_in5(snapshot_block[511:256]),.probe_in6(snapshot_status),.probe_in7({bars_diagnostic[127:16],uart_debug_dropped[15:0]}),
  `else
    .probe_in3(debug_performance),
  `endif
    .probe_out0(virtual_sw),.probe_out1(debug_control)
`ifdef LCD_SNAPSHOT
    ,.probe_out2(debug_read_command)
`endif
  );
`ifndef LCD_SNAPSHOT
  assign debug_read_command=0;
`endif
`else
  assign virtual_sw=0;assign debug_control=0;
  assign debug_read_command=0;
`endif
  assign led=ss[14]?{observed_cap_error,sink_error}:
    {(|error),frames[3:0],(|sink_error),(|observed_cap_error),config_error,ss[15],active_internal,
     frame_complete,sink_busy,cap_busy,background_done,lcd_initialized,ready};
endmodule
