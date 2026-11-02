`timescale 1ns/1ps
// 识别子系统：一份小图RAM，由自主采集或人工回放独占；视频无需等待识别。
 // AUTO可动态定位；ROI参数为初始搜索范围，人工协议独立指定其ROI。
module plate_recognition_subsystem #(parameter AUTO_LOCATE=0,SKIP_CHINESE=0,SPLIT_TOUCHING=0,
 parameter [7:0] ROI_X0=8'd26,ROI_Y0=8'd35,ROI_X1=8'd158,ROI_Y1=8'd87
)(
 input wire clk,rst,manual_mode,diagnostic_mode,recognition_enable,white_characters,uart_rxd,
 input wire source_start,source_valid,source_done,source_error,
 input wire[7:0]source_pixel,input wire[9:0]source_x,input wire[8:0]source_y,
 output wire uart_txd,output wire[127:0]status,
 // 完整结果旁路给屏幕；接收端没有ready，不能阻塞识别。
 output wire display_enabled,display_result_event,
 output wire[7:0]display_result_status,output wire[6:0]display_result_count,
 output wire[63:0]display_result_text,
 // 定位完成事件只供显示旁路；坐标即分割器实际采用的ROI，半开区间。
 output wire display_roi_event,display_roi_valid,
 output wire[7:0]display_roi_x0,display_roi_y0,display_roi_x1,display_roi_y1
);
 wire auto_mode=recognition_enable&&!manual_mode&&!diagnostic_mode;
 reg[3:0]last_mode;
 // SW5只作用于自主OCR；切换字色沿用任务中止/清除机制，不混用新旧极性。
 wire[3:0]mode={auto_mode&&white_characters,recognition_enable,manual_mode,diagnostic_mode};
 wire mode_changed=mode!=last_mode;
 always @(posedge clk)if(rst)last_mode<=0;else last_mode<=mode;
 wire manual_rst=rst||!manual_mode||mode_changed;
 wire auto_rst=rst||!auto_mode||mode_changed;
 wire m_reset,a_reset;
 // 切换所有权时中止旧任务，防止把半幅上传图交给下一种模式。
 // 退出识别立即撤销RAM所有权；手动回放仍可在任意显示模式下独立使用。
 wire work_rst=rst||mode_changed||diagnostic_mode||(!manual_mode&&!recognition_enable)||(manual_mode?m_reset:a_reset);
 wire m_tx,a_tx;
 wire m_fw,a_fw;wire[14:0]m_fa,a_fa;wire[7:0]m_fd,a_fd;
 wire m_ns,a_ns,m_ss,a_ss,m_cs,a_cs,m_cwe,a_cwe;
 wire[9:0]m_ca,a_ca;wire[7:0]m_cd,a_cd;
 wire[7:0]m_x,m_y,m_w,m_h,m_x0,m_y0,m_x1,m_y1;
 wire[7:0]a_x,a_y,a_w,a_h,a_x0,a_y0,a_x1,a_y1;
 wire[1:0]m_flags,a_flags;
 wire auto_busy;reg active_white_characters;
 // 原图RAM与定位不反相，仅分割和归一化复用既有flags[1]；每次完整采集锁存。
 always @(posedge clk)begin
  if(auto_rst)active_white_characters<=0;
  else if(source_start&&!auto_busy)active_white_characters<=white_characters;
 end
 assign a_flags={active_white_characters,1'b0};
 wire[31:0]m_accepted,m_crc,m_rx;
 wire nb,nd,ne,npw;wire[31:0]nc;wire[9:0]npa;wire[7:0]npd;
 wire sb,sd,sbw;wire[7:0]se,sbx,sby,sbww,sbh;wire[5:0]sbi;wire[6:0]sbc;
 wire[31:0]sc;wire[14:0]sra;wire[7:0]srd;
 wire cb,cd,csv;wire[5:0]csi;wire signed[31:0]csd;wire[31:0]cc;
 wire[7:0]bx=manual_mode?m_x:a_x,by=manual_mode?m_y:a_y;
 wire[7:0]bw=manual_mode?m_w:a_w,bh=manual_mode?m_h:a_h;
 wire[7:0]rx0=manual_mode?m_x0:a_x0,ry0=manual_mode?m_y0:a_y0;
 wire[7:0]rx1=manual_mode?m_x1:a_x1,ry1=manual_mode?m_y1:a_y1;
 wire[1:0]fl=manual_mode?m_flags:a_flags;
 wire[7:0]located_x0,located_y0,located_x1,located_y1;
 plate_segment_frontend #(.AUTO_LOCATE(AUTO_LOCATE),.SKIP_CHINESE(SKIP_CHINESE),.SPLIT_TOUCHING(SPLIT_TOUCHING)) segment_characters(.clk(clk),.rst(work_rst),.start(manual_mode?m_ss:a_ss),.locate_enable(auto_mode),
  .roi_x0(rx0),.roi_y0(ry0),.roi_x1(rx1),.roi_y1(ry1),.flags(fl),
  .busy(sb),.done(sd),.error(se),.cycles(sc),.frame_read_addr(sra),.frame_read_data(srd),
  .box_we(sbw),.box_index(sbi),.box_x(sbx),.box_y(sby),.box_w(sbww),.box_h(sbh),.box_count(sbc),
  .selected_x0(located_x0),.selected_y0(located_y0),.selected_x1(located_x1),.selected_y1(located_y1));
 char_normalizer #(.ENABLE_SCAN(1)) normalize_character(.clk(clk),.rst(work_rst),.start(manual_mode?m_ns:a_ns),
  .scan_en(sb),.scan_addr(sra),.scan_data(srd),
  .frame_we(!work_rst&&(manual_mode?m_fw:a_fw)),.frame_addr(manual_mode?m_fa:a_fa),.frame_data(manual_mode?m_fd:a_fd),
  .box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),
  .roi_x0(manual_mode?m_x0:located_x0),.roi_y0(manual_mode?m_y0:located_y0),
  .roi_x1(manual_mode?m_x1:located_x1),.roi_y1(manual_mode?m_y1:located_y1),.flags(fl),
  .busy(nb),.done(nd),.error(ne),.cycles(nc),.pixel_we(npw),.pixel_addr(npa),.pixel_data(npd));
 cnn_core recognizer(.clk(clk),.rst(work_rst),.start(manual_mode?m_cs:a_cs),
  .in_we(!work_rst&&(manual_mode?m_cwe:a_cwe)),.in_addr(manual_mode?m_ca:a_ca),.in_data(manual_mode?m_cd:a_cd),
  .busy(cb),.done(cd),.score_valid(csv),.score_index(csi),.score_data(csd),.cycles(cc));
 norm_uart_bridge manual_transport(.clk(clk),.rst(manual_rst),.uart_rxd(uart_rxd),.uart_txd(m_tx),
  .seg_start(m_ss),.seg_busy(sb),.seg_done(sd),.seg_error(se),.seg_cycles(sc),
  .seg_box_we(sbw),.seg_box_index(sbi),.seg_box_x(sbx),.seg_box_y(sby),.seg_box_w(sbww),.seg_box_h(sbh),.seg_box_count(sbc),
  .worker_reset(m_reset),.frame_we(m_fw),.frame_addr(m_fa),.frame_data(m_fd),
  .norm_start(m_ns),.box_x(m_x),.box_y(m_y),.box_w(m_w),.box_h(m_h),
  .roi_x0(m_x0),.roi_y0(m_y0),.roi_x1(m_x1),.roi_y1(m_y1),.flags(m_flags),
  .norm_busy(nb),.norm_done(nd),.norm_error(ne),.norm_cycles(nc),.norm_pixel_we(npw),.norm_pixel_addr(npa),.norm_pixel_data(npd),
  .core_start(m_cs),.core_in_we(m_cwe),.core_in_addr(m_ca),.core_in_data(m_cd),.core_busy(cb),.core_done(cd),
  .score_valid(csv),.score_index(csi),.score_data(csd),.core_cycles(cc),.accepted(m_accepted),.crc_errors(m_crc),.rx_errors(m_rx));
 wire cap_begin,cap_end,cap_abort,seg_event,char_begin,char_event,result_event;
 wire[31:0]frame_id,capture_tick,raw_crc,seg_elapsed,norm_elapsed,core_elapsed,elapsed_cycles;
 wire[31:0]bad_captures,skipped_frames,completed_frames,publisher_dropped,publisher_packets;
 wire[2047:0]boxes_flat;wire[511:0]text_flat;
 wire[6:0]box_count,completed_chars;wire[7:0]seg_status,result_status,best_ascii;
 wire[5:0]char_index,best_index;wire[31:0]char_box;
 plate_auto_controller #(.ROI_X0(ROI_X0),.ROI_Y0(ROI_Y0),.ROI_X1(ROI_X1),.ROI_Y1(ROI_Y1)) automatic_recognition(.clk(clk),.rst(auto_rst),
  .source_start(source_start),.source_valid(source_valid),.source_pixel(source_pixel),.source_x(source_x),.source_y(source_y),
  .source_done(source_done),.source_error(source_error),
  .worker_reset(a_reset),.frame_we(a_fw),.frame_addr(a_fa),.frame_data(a_fd),
  .seg_start(a_ss),.norm_start(a_ns),.core_start(a_cs),.core_in_we(a_cwe),.core_in_addr(a_ca),.core_in_data(a_cd),
  .box_x(a_x),.box_y(a_y),.box_w(a_w),.box_h(a_h),.roi_x0(a_x0),.roi_y0(a_y0),.roi_x1(a_x1),.roi_y1(a_y1),.flags(),
  .seg_busy(sb),.seg_done(sd),.seg_error(se),.seg_cycles(sc),.seg_box_we(sbw),.seg_box_index(sbi),
  .seg_box_x(sbx),.seg_box_y(sby),.seg_box_w(sbww),.seg_box_h(sbh),.seg_box_count(sbc),
  .norm_busy(nb),.norm_done(nd),.norm_error(ne),.norm_cycles(nc),.norm_pixel_we(npw),.norm_pixel_addr(npa),.norm_pixel_data(npd),
  .core_busy(cb),.core_done(cd),.core_cycles(cc),.score_valid(csv),.score_index(csi),.score_data(csd),
  .cap_begin(cap_begin),.cap_end(cap_end),.cap_abort(cap_abort),.frame_id(frame_id),.capture_tick(capture_tick),.raw_crc(raw_crc),
  .seg_event(seg_event),.boxes_flat(boxes_flat),.box_count(box_count),.seg_status(seg_status),.seg_elapsed(seg_elapsed),
  .char_begin(char_begin),.char_index(char_index),.char_box(char_box),.char_event(char_event),
  .best_index(best_index),.best_ascii(best_ascii),.norm_elapsed(norm_elapsed),.core_elapsed(core_elapsed),
  .result_event(result_event),.result_status(result_status),.completed_chars(completed_chars),.text_flat(text_flat),
  .elapsed_cycles(elapsed_cycles),.bad_captures(bad_captures),.skipped_frames(skipped_frames),.busy(auto_busy),.completed_frames(completed_frames));
 // 观测模块只有输入事件，没有ready反馈；串口断开、接收慢均不影响识别或视频。
 plate_auto_uart #(.DYNAMIC_ROI(AUTO_LOCATE),.PREFIX_FILTER(SKIP_CHINESE),.SPLIT_TOUCHING(SPLIT_TOUCHING)) automatic_observer(.clk(clk),.rst(auto_rst),.uart_txd(a_tx),.dropped(publisher_dropped),.packets(publisher_packets),
  .seg_roi_x0(located_x0),.seg_roi_y0(located_y0),.seg_roi_x1(located_x1),.seg_roi_y1(located_y1),
  .cap_begin(cap_begin),.cap_end(cap_end),.cap_abort(cap_abort),.frame_we(a_fw),.frame_addr(a_fa),.frame_data(a_fd),
  .frame_id(frame_id),.capture_tick(capture_tick),.raw_crc(raw_crc),.roi_x0(a_x0),.roi_y0(a_y0),.roi_x1(a_x1),.roi_y1(a_y1),.flags(a_flags),
  .seg_event(seg_event),.boxes_flat(boxes_flat),.box_count(box_count),.seg_status(seg_status),.seg_elapsed(seg_elapsed),
  .char_begin(char_begin),.char_index(char_index),.char_box(char_box),.norm_pixel_we(npw),.norm_pixel_addr(npa),.norm_pixel_data(npd),
  .norm_done(nd),.norm_cycles(nc),.score_valid(csv),.score_index(csi),.score_data(csd),
  .char_event(char_event),.best_index(best_index),.best_ascii(best_ascii),.norm_elapsed(norm_elapsed),.core_elapsed(core_elapsed),
  .result_event(result_event),.result_status(result_status),.completed_chars(completed_chars),.text_flat(text_flat),
  .elapsed_cycles(elapsed_cycles),.bad_captures(bad_captures),.skipped_frames(skipped_frames));
 assign uart_txd=manual_mode?m_tx:a_tx;
 // 采集中止也撤销旧框，防止失败后保留上次区域误导摆放。
 assign display_roi_event=(seg_event||cap_abort)&&!auto_rst;
 assign display_roi_valid=seg_event&&!cap_abort&&seg_status==0 && located_x0<located_x1 && located_y0<located_y1;
 assign display_roi_x0=located_x0;assign display_roi_y0=located_y0;
 assign display_roi_x1=located_x1;assign display_roi_y1=located_y1;
 assign display_enabled=auto_mode&&!auto_rst;
 assign display_result_event=result_event&&!auto_rst;
 assign display_result_status=result_status;
 assign display_result_count=completed_chars;
 assign display_result_text=text_flat[63:0];
 assign status=manual_mode?{m_accepted,m_crc,m_rx,cc}:{completed_frames,bad_captures,publisher_dropped,elapsed_cycles};
endmodule

