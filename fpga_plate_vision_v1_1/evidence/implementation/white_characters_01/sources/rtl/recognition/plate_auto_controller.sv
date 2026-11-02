`timescale 1ns/1ps
module plate_auto_controller #(
 parameter integer CAPTURE_TIMEOUT_CYCLES=10000000,
 parameter integer SEG_TIMEOUT_CYCLES=100000000,
 parameter integer NORM_TIMEOUT_CYCLES=10000000,
 parameter integer CORE_TIMEOUT_CYCLES=10000000,
 parameter [7:0] ROI_X0=8'd26,ROI_Y0=8'd35,ROI_X1=8'd158,ROI_Y1=8'd87
)(
 input wire clk,rst,source_start,source_valid,source_done,source_error,
 input wire[7:0]source_pixel,input wire[9:0]source_x,input wire[8:0]source_y,
 input wire seg_busy,seg_done,input wire[7:0]seg_error,input wire[31:0]seg_cycles,
 input wire seg_box_we,input wire[5:0]seg_box_index,input wire[7:0]seg_box_x,seg_box_y,seg_box_w,seg_box_h,input wire[6:0]seg_box_count,
 input wire norm_busy,norm_done,norm_error,input wire[31:0]norm_cycles,
 input wire norm_pixel_we,input wire[9:0]norm_pixel_addr,input wire[7:0]norm_pixel_data,
 input wire core_busy,core_done,input wire[31:0]core_cycles,
 input wire score_valid,input wire[5:0]score_index,input wire signed[31:0]score_data,
 output reg worker_reset,frame_we,output reg[14:0]frame_addr,output reg[7:0]frame_data,
 output reg seg_start,norm_start,core_start,core_in_we,output reg[9:0]core_in_addr,output reg[7:0]core_in_data,
 output reg[7:0]box_x,box_y,box_w,box_h,
 output wire[7:0]roi_x0,roi_y0,roi_x1,roi_y1,output wire[1:0]flags,
 output reg cap_begin,cap_end,cap_abort,
 output reg[31:0]frame_id,capture_tick,raw_crc,
 output reg seg_event,output reg[2047:0]boxes_flat,output reg[6:0]box_count,output reg[7:0]seg_status,output reg[31:0]seg_elapsed,
 output reg char_begin,output reg[5:0]char_index,output reg[31:0]char_box,
 output reg char_event,output reg[5:0]best_index,output reg[7:0]best_ascii,output reg[31:0]norm_elapsed,core_elapsed,
 output reg result_event,output reg[7:0]result_status,output reg[6:0]completed_chars,output reg[511:0]text_flat,
 output reg[31:0]elapsed_cycles,bad_captures,skipped_frames,output wire busy,output reg[31:0]completed_frames
);
 // 结果状态：01源格式/源错误，02采集超时，10分割错误，11分割超时，12框错误；
 // 20归一化错误，21归一化超时，22像素错误，30分数错误，31核心超时。
 // frame_id 固定为已接纳帧编号；source_seq 对所有 start 递增，忙时帧只计 skipped。
 // 空分割是正常完成：零字符、零尾部。completed_frames 只统计状态为零的结果。
 // 固定 ROI 需要按场景标定，不是自动车牌定位；右下端点不包含。
 // 合法区域满足 x0<x1<=160、y0<y1<=120；无任何遥测 ready 输入。
 assign roi_x0=ROI_X0;assign roi_y0=ROI_Y0;assign roi_x1=ROI_X1;assign roi_y1=ROI_Y1;assign flags=2'b00;
 localparam[3:0] IDLE=0,CAPTURE=1,CAP_DRAIN=2,SEG_LAUNCH=3,SEG_WAIT=4,
  CHAR_PREP=5,NORM_LAUNCH=6,NORM_WAIT=7,CORE_LAUNCH=8,CORE_WAIT=9,CHAR_REPORT=10,REPORT=11,RELEASE=12,CHAR_NEXT=13;
 reg[3:0]state;
 assign busy=(state!=IDLE);
 reg[31:0]tick,source_seq,watchdog,crc_state;
 reg[9:0]expected_x;reg[8:0]expected_y;
 reg[18:0]source_count;reg[14:0]sample_count;
 reg[6:0]received_boxes;
 reg[9:0]received_pixels;
 reg[35:0]seen_scores;
 reg signed[31:0]best_score;
 reg best_seen;
 wire sample_select=(source_x[1:0]==2'b11)&&(source_y[1:0]==2'b00);
 wire[18:0]capture_count_next=source_count+(source_valid?19'd1:19'd0);
 wire[6:0]box_count_next=received_boxes+(seg_box_we?7'd1:7'd0);
 wire[9:0]pixel_count_next=received_pixels+(norm_pixel_we?10'd1:10'd0);
 wire[35:0]score_mask=(36'b1<<score_index);
 wire[35:0]score_seen_next=seen_scores|(score_valid?score_mask:36'b0);
 wire bad_box=seg_box_we&&((received_boxes>=64)||(seg_box_index!=received_boxes)||
  (seg_box_w==0)||(seg_box_h==0)||({1'b0,seg_box_x}+{1'b0,seg_box_w}>160)||({1'b0,seg_box_y}+{1'b0,seg_box_h}>120));
 wire bad_pixel=norm_pixel_we&&((received_pixels>=768)||(norm_pixel_addr!=received_pixels));
 wire bad_score=score_valid&&((score_index>=36)||((seen_scores&score_mask)!=0));
 function automatic[31:0]crc_byte(input[31:0]c,input[7:0]b);
  reg[31:0]v;integer k;begin v=c^{24'd0,b};for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 function automatic[7:0]class_ascii(input[5:0]index);
  begin class_ascii=(index<10)?8'd48+{2'b0,index}:8'd55+{2'b0,index};end
 endfunction
 // 故障只结束当前任务，复位工作单元，下一源帧可重新获得缓存。
 task automatic fail_task(input[7:0]code,input bit capture_fault);
  begin
   result_status<=code;worker_reset<=1;state<=REPORT;frame_we<=0;core_in_we<=0;
   if(capture_fault)begin cap_abort<=1;bad_captures<=bad_captures+1'b1;end
  end
 endtask
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;tick<=0;source_seq<=0;watchdog<=0;crc_state<=32'hffffffff;
   expected_x<=0;expected_y<=0;source_count<=0;sample_count<=0;received_boxes<=0;received_pixels<=0;seen_scores<=0;best_score<=0;best_seen<=0;
   worker_reset<=1;frame_we<=0;frame_addr<=0;frame_data<=0;
   seg_start<=0;norm_start<=0;core_start<=0;core_in_we<=0;core_in_addr<=0;core_in_data<=0;
   box_x<=0;box_y<=0;box_w<=0;box_h<=0;
   cap_begin<=0;cap_end<=0;cap_abort<=0;frame_id<=0;capture_tick<=0;raw_crc<=0;
   seg_event<=0;boxes_flat<=0;box_count<=0;seg_status<=0;seg_elapsed<=0;
   char_begin<=0;char_index<=0;char_box<=0;char_event<=0;best_index<=0;best_ascii<=0;norm_elapsed<=0;core_elapsed<=0;
   result_event<=0;result_status<=0;completed_chars<=0;text_flat<=0;elapsed_cycles<=0;bad_captures<=0;skipped_frames<=0;completed_frames<=0;
  end else begin
   tick<=tick+1'b1;
   worker_reset<=0;frame_we<=0;seg_start<=0;norm_start<=0;core_start<=0;core_in_we<=0;
   cap_begin<=0;cap_end<=0;cap_abort<=0;seg_event<=0;char_begin<=0;char_event<=0;result_event<=0;
   if(source_start)begin source_seq<=source_seq+1'b1;if(state!=IDLE)skipped_frames<=skipped_frames+1'b1;end
   case(state)
    IDLE:if(source_start)begin
     frame_id<=source_seq+1'b1;capture_tick<=tick;cap_begin<=1;result_status<=0;
     completed_chars<=0;text_flat<=0;boxes_flat<=0;box_count<=0;seg_status<=0;seg_elapsed<=0;char_index<=0;norm_elapsed<=0;core_elapsed<=0;
     crc_state<=32'hffffffff;raw_crc<=0;sample_count<=0;watchdog<=0;state<=CAPTURE;
     // start 可以与 (0,0) 的有效像素同拍。
     source_count<=source_valid?19'd1:19'd0;expected_x<=source_valid?10'd1:10'd0;expected_y<=0;
     if(source_error||source_done||(source_valid&&((source_x!=0)||(source_y!=0))))fail_task(8'h01,1);
    end
    CAPTURE:begin
     watchdog<=watchdog+1'b1;
     if(source_error||source_start||
       (source_valid&&((source_count>=307200)||(source_x!=expected_x)||(source_y!=expected_y))))fail_task(8'h01,1);
     else begin
      if(source_valid)begin
       source_count<=capture_count_next;
       if(expected_x==639)begin expected_x<=0;expected_y<=expected_y+1'b1;end else expected_x<=expected_x+1'b1;
       if(sample_select)begin
        frame_we<=1;frame_addr<=sample_count;frame_data<=source_pixel;sample_count<=sample_count+1'b1;
        crc_state<=crc_byte(crc_state,source_pixel);
       end
      end
      if(source_done)begin
       if(capture_count_next!=307200||sample_count!=19200)fail_task(8'h01,1);
       else begin state<=CAP_DRAIN;raw_crc<=~crc_state;end
      end else if(watchdog>=CAPTURE_TIMEOUT_CYCLES-1)fail_task(8'h02,1);
     end
    end
    // done 完整性检查后再发完成事件，帧 RAM 已提交最后一次写。
    CAP_DRAIN:begin cap_end<=1;state<=SEG_LAUNCH;end
    SEG_LAUNCH:begin
     if(!seg_busy)begin seg_start<=1;received_boxes<=0;watchdog<=0;state<=SEG_WAIT;end
     else begin seg_status<=8'h12;seg_event<=1;fail_task(8'h12,0);end
    end
    SEG_WAIT:begin
     watchdog<=watchdog+1'b1;
     if(bad_box)begin seg_status<=8'h12;seg_elapsed<=seg_cycles;seg_event<=1;fail_task(8'h12,0);end
     else begin
      if(seg_box_we)begin boxes_flat[seg_box_index*32+:32]<={seg_box_h,seg_box_w,seg_box_y,seg_box_x};received_boxes<=box_count_next;end
      if(seg_done)begin
       seg_elapsed<=seg_cycles;seg_event<=1;box_count<=seg_box_count;
       if(seg_error!=0)begin seg_status<=seg_error;fail_task(8'h10,0);end
       else if(seg_box_count>64||seg_box_count!=box_count_next)begin seg_status<=8'h12;fail_task(8'h12,0);end
       else begin seg_status<=0;char_index<=0;state<=(seg_box_count==0)?REPORT:CHAR_PREP;end
      end else if(watchdog>=SEG_TIMEOUT_CYCLES-1)begin seg_elapsed<=seg_cycles;seg_status<=8'h11;seg_event<=1;fail_task(8'h11,0);end
     end
    end
    CHAR_PREP:begin
     char_box<=boxes_flat[char_index*32+:32];
     {box_h,box_w,box_y,box_x}<=boxes_flat[char_index*32+:32];
     char_begin<=1;state<=NORM_LAUNCH;
    end
    NORM_LAUNCH:begin
     if(!norm_busy&&!core_busy)begin norm_start<=1;received_pixels<=0;watchdog<=0;state<=NORM_WAIT;end
     else fail_task(8'h20,0);
    end
    NORM_WAIT:begin
     watchdog<=watchdog+1'b1;
     if(bad_pixel)fail_task(8'h22,0);
     else begin
      if(norm_pixel_we)begin core_in_we<=1;core_in_addr<=norm_pixel_addr;core_in_data<=norm_pixel_data;received_pixels<=pixel_count_next;end
      if(norm_done)begin
       norm_elapsed<=norm_cycles;
       if(norm_error)fail_task(8'h20,0);
       else if(pixel_count_next!=768)fail_task(8'h22,0);
       else state<=CORE_LAUNCH;
      end else if(watchdog>=NORM_TIMEOUT_CYCLES-1)fail_task(8'h21,0);
     end
    end
    CORE_LAUNCH:begin
     if(!core_busy)begin core_start<=1;watchdog<=0;seen_scores<=0;best_seen<=0;best_score<=32'sh80000000;best_index<=0;state<=CORE_WAIT;end
     else fail_task(8'h30,0);
    end
    CORE_WAIT:begin
     watchdog<=watchdog+1'b1;
     if(bad_score)fail_task(8'h30,0);
     else begin
      if(score_valid)begin
       seen_scores<=score_seen_next;
       // signed 分数；乱序输出时并列也选择较小类别编号。
       if(!best_seen||($signed(score_data)>$signed(best_score))||((score_data==best_score)&&(score_index<best_index)))begin best_score<=score_data;best_index<=score_index;end
       best_seen<=1;
      end
      if(core_done)begin
       core_elapsed<=core_cycles;
       if(score_seen_next!=36'hfffffffff)fail_task(8'h30,0);else state<=CHAR_REPORT;
      end else if(watchdog>=CORE_TIMEOUT_CYCLES-1)fail_task(8'h31,0);
     end
    end
    CHAR_REPORT:begin
     best_ascii<=class_ascii(best_index);char_event<=1;text_flat[char_index*8+:8]<=class_ascii(best_index);completed_chars<=completed_chars+1'b1;
     if({1'b0,char_index}+7'd1==box_count)state<=REPORT;
     else state<=CHAR_NEXT;
    end
    CHAR_NEXT:begin char_index<=char_index+1'b1;state<=CHAR_PREP;end
    REPORT:begin
     result_event<=1;elapsed_cycles<=tick-capture_tick;
     if(result_status==0)completed_frames<=completed_frames+1'b1;
     state<=RELEASE;
    end
    RELEASE:state<=IDLE;
    default:begin worker_reset<=1;state<=IDLE;end
   endcase
  end
 end
endmodule



