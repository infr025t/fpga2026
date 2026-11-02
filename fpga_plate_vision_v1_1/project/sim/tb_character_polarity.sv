`timescale 1ns/1ps
// 实际识别子系统：显示模式退出中止半帧，重新进入只接纳新完整任务。
module tb_character_polarity;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,manual_mode=0,diagnostic_mode=0,recognition_enable=0;
 reg white_characters=0;
 reg source_start=0,source_valid=0,source_done=0,source_error=0;
 reg[7:0]source_pixel=100;reg[9:0]source_x=0;reg[8:0]source_y=0;
 wire display_roi_event,display_roi_valid;wire[7:0]display_roi_x0,display_roi_y0,display_roi_x1,display_roi_y1;
 wire uart_txd,display_enabled,display_result_event;wire[127:0]status;
 wire[7:0]display_result_status;wire[6:0]display_result_count;wire[63:0]display_result_text;
 plate_recognition_subsystem #(.AUTO_LOCATE(1),.SKIP_CHINESE(1),.SPLIT_TOUCHING(1)) dut(.uart_rxd(1'b1),.*);
 integer writes=0,begins=0;
 always @(posedge clk)if(!rst)begin
  if(dut.a_fw)writes=writes+1;
  if(dut.cap_begin)begins=begins+1;
 end
 task partial_frame;begin
  @(negedge clk);source_start=1;@(negedge clk);source_start=0;
  for(integer x=0;x<80;x=x+1)begin source_valid=1;source_x=x;source_y=0;@(negedge clk);end
  source_valid=0;
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  partial_frame();repeat(4)@(negedge clk);
  if(writes||begins||display_enabled||!dut.work_rst)$fatal(1,"RAW must not start OCR");
  recognition_enable=1;repeat(4)@(negedge clk);partial_frame();repeat(4)@(negedge clk);
  if(writes==0||begins!=1||!display_enabled)$fatal(1,"OCR admission");
  recognition_enable=0;repeat(4)@(negedge clk);
  if(dut.auto_busy||dut.a_fw||display_enabled||display_result_event||!dut.work_rst)$fatal(1,"exit must invalidate partial frame");
  writes=0;partial_frame();repeat(4)@(negedge clk);if(writes)$fatal(1,"EDGE/RAW writes recognition RAM");
  manual_mode=1;repeat(4)@(negedge clk);if(dut.manual_rst||dut.work_rst||display_enabled)$fatal(1,"manual independent of display mode");
  manual_mode=0;recognition_enable=1;repeat(4)@(negedge clk);partial_frame();repeat(4)@(negedge clk);
  if(begins!=2||writes==0)$fatal(1,"OCR fresh restart");
  // 切换字色中止半帧；下一次从原灰度重新采集，模式不可混用。
  white_characters=1;repeat(4)@(negedge clk);
  if(dut.auto_busy||dut.a_fw||dut.a_flags!=0)$fatal(1,"polarity change did not cancel active capture");
  writes=0;partial_frame();repeat(4)@(negedge clk);
  if(begins!=3||writes!=20||dut.a_flags!==2||dut.a_fd!==100)$fatal(1,"white capture must retain raw samples and latch flags=2");
  source_error=1;@(posedge clk);#1;
  if(!display_roi_event||display_roi_valid)$fatal(1,"capture abort must clear stale ROI");
  @(negedge clk);source_error=0;
  diagnostic_mode=1;repeat(4)@(negedge clk);if(!dut.work_rst||display_enabled)$fatal(1,"diagnostic ownership");
  $display("PASS character polarity: RAW/EDGE disabled, switch cancels partial capture, new white frame keeps raw bytes, flags=2, abort clears ROI");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
