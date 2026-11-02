`timescale 1ns/1ps
module tb_plate_auto_controller;
 reg clk=0; always #5 clk=~clk;
 reg rst=1,source_start=0,source_valid=0,source_done=0,source_error=0;
 reg [7:0] source_pixel=0; reg[9:0]source_x=0; reg[8:0]source_y=0;
 reg seg_busy=0,seg_done=0; reg[7:0]seg_error=0; reg[31:0]seg_cycles=0;
 reg seg_box_we=0; reg[5:0]seg_box_index=0; reg[7:0]seg_box_x=0,seg_box_y=0,seg_box_w=0,seg_box_h=0; reg[6:0]seg_box_count=0;
 reg norm_busy=0,norm_done=0,norm_error=0,norm_pixel_we=0; reg[31:0]norm_cycles=0;reg[9:0]norm_pixel_addr=0;reg[7:0]norm_pixel_data=0;
 reg core_busy=0,core_done=0,score_valid=0;reg[31:0]core_cycles=0;reg[5:0]score_index=0;reg signed[31:0]score_data=0;
 wire worker_reset,frame_we,seg_start,norm_start,core_start,core_in_we;
 wire[14:0]frame_addr;wire[7:0]frame_data;wire[9:0]core_in_addr;wire[7:0]core_in_data;
 wire[7:0]box_x,box_y,box_w,box_h,roi_x0,roi_y0,roi_x1,roi_y1;wire[1:0]flags;
 wire cap_begin,cap_end,cap_abort,seg_event,char_begin,char_event,result_event,busy;
 wire[31:0]frame_id,capture_tick,raw_crc,seg_elapsed,norm_elapsed,core_elapsed,elapsed_cycles,bad_captures,skipped_frames,completed_frames;
 wire[2047:0]boxes_flat;wire[6:0]box_count,completed_chars;wire[7:0]seg_status,result_status,best_ascii;wire[5:0]char_index,best_index;wire[31:0]char_box;wire[511:0]text_flat;
 plate_auto_controller #(.CAPTURE_TIMEOUT_CYCLES(350000),.SEG_TIMEOUT_CYCLES(100),.NORM_TIMEOUT_CYCLES(2000),.CORE_TIMEOUT_CYCLES(100)) dut(.*);
 integer cycle=0,writes=0,cap_cycle=0,cap_ends=0,aborts=0,chars=0,results=0,seg_starts=0,norm_starts=0,core_starts=0,core_writes=0;
 integer mode=0,seg_step=-1,norm_step=-1,core_step=-1;
 reg[31:0] crc_ref=32'hffffffff;
 reg[7:0] last_status=0;reg[6:0]last_completed=0;reg[511:0]last_text=0;
 function automatic[31:0] crc_byte(input[31:0]c,input[7:0]b);
  reg[31:0]v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 task check(input bit ok,input string msg);begin if(!ok)$fatal(1,"FAIL %s cycle=%0d mode=%0d",msg,cycle,mode);end endtask
 always @(posedge clk) begin
  cycle=cycle+1;
  if(!rst)begin
   if(cap_begin)begin cap_cycle=cycle;writes=0;crc_ref=32'hffffffff;end
   if(frame_we)begin
    check(frame_addr==writes,"sample address contiguous");
    check(frame_data==((((writes%160)*4+3)^((writes/160)*4))&255),"sample phase x3 y0");
    check(cycle-cap_cycle>=3,"capture event precedes sampled writes");
    crc_ref=crc_byte(crc_ref,frame_data);writes=writes+1;
   end
   if(cap_end)begin check(writes==19200,"full sampled length");check(raw_crc==~crc_ref,"raw CRC");cap_ends=cap_ends+1;end
   if(cap_abort)aborts=aborts+1;
   if(seg_start)begin check(writes==19200&&cap_ends>0,"no segmentation before validated frame");seg_starts=seg_starts+1;end
   if(char_begin)check(char_box==((32'd30<<24)|(32'd10<<16)|(32'd36<<8)|(8'd30+char_index*12)),"character box order");
   if(norm_start)begin check(box_x==30+norm_starts*12,"normalizer selected box");norm_starts=norm_starts+1;end
   if(core_in_we)begin check(core_in_addr==(core_writes%768),"core input addresses");check(core_in_data==(core_writes%256),"core input bytes");core_writes=core_writes+1;end
   if(core_start)begin check(core_writes==768*(core_starts+1),"CNN only after 768 pixels");core_starts=core_starts+1;end
   if(char_event)begin check(char_index==chars,"character result index remains stable");check(best_index==3&&best_ascii=="3","signed negative argmax and low-index tie");chars=chars+1;end
   if(result_event)begin if(result_status==0)check(!worker_reset,"successful result does not reset workers");results=results+1;last_status=result_status;last_completed=completed_chars;last_text=text_flat;end
   if(seg_busy||norm_busy||core_busy)check(!frame_we,"frozen frame ownership");
  end
 end
 // 用可控工作单元故障验证控制器，不替代真实算法联仿。
 always @(negedge clk) begin
  seg_done=0;seg_box_we=0;norm_done=0;norm_pixel_we=0;core_done=0;score_valid=0;
  if(rst||worker_reset)begin seg_busy=0;norm_busy=0;core_busy=0;seg_step=-1;norm_step=-1;core_step=-1;end
  else begin
   if(seg_start)begin seg_busy=1;seg_step=0;seg_error=0;seg_box_count=0;end
   else if(seg_step>=0)begin
    if(mode==2)begin seg_error=8'd9;seg_done=1;seg_busy=0;seg_step=-1;end
    else if(mode==3)begin end
    else if(mode==1)begin seg_done=1;seg_busy=0;seg_step=-1;end
    else begin
     seg_box_we=1;seg_box_index=seg_step;seg_box_x=30+seg_step*12;seg_box_y=36;seg_box_w=10;seg_box_h=30;
     if(mode==10)seg_box_index=0;
     if(seg_step==1)begin seg_done=1;seg_busy=0;seg_box_count=(mode==14)?1:2;seg_step=-1;end else seg_step=seg_step+1;
    end
    seg_cycles=17;
   end
   if(norm_start)begin norm_busy=1;norm_step=0;norm_error=0;end
   else if(norm_step>=0)begin
    if(mode==4)begin norm_done=1;norm_error=1;norm_busy=0;norm_step=-1;end
    else if(mode==5)begin end
    else begin
     norm_pixel_we=1;norm_pixel_addr=norm_step;norm_pixel_data=norm_step;
     if(mode==11&&norm_step==10)norm_pixel_addr=9;
     if(norm_step==767||(mode==12&&norm_step==766))begin norm_done=1;norm_busy=0;norm_step=-1;end else norm_step=norm_step+1;
    end
    norm_cycles=1001;
   end
   if(core_start)begin core_busy=1;core_step=35;end
   else if(core_step>=0)begin
    if(mode!=8)begin
     score_valid=1;score_index=core_step;score_data=(core_step==3||core_step==7)?-32'sd1:-32'sd100;
     if(mode==6&&core_step==20)score_valid=0;
     if(mode==7&&core_step==20)score_index=21;
     if(mode==13&&core_step==20)score_index=63;
     if(core_step==0)begin core_done=1;core_busy=0;core_step=-1;end else core_step=core_step-1;
    end
    core_cycles=2222;
   end
  end
 end
 task reset_case(input integer next_mode);begin
  @(negedge clk);rst=1;source_start=0;source_valid=0;source_done=0;source_error=0;
  repeat(4)@(negedge clk);rst=0;mode=next_mode;
  writes=0;cap_ends=0;aborts=0;chars=0;results=0;seg_starts=0;norm_starts=0;core_starts=0;core_writes=0;
  repeat(3)@(negedge clk);
 end endtask
 task send_frame(input integer fault,input bit start_with_pixel);integer i;begin
  if(!start_with_pixel)begin @(negedge clk);source_start=1;@(negedge clk);source_start=0;end
  for(i=0;i<307200;i=i+1)begin
   @(negedge clk);source_start=start_with_pixel&&(i==0);source_valid=1;source_x=i%640;source_y=i/640;source_pixel=(i%640)^(i/640);
   source_done=(i==307199)&&(fault!=3)&&(fault!=6);source_error=(fault==5)&&(i==50);
   if(fault==1&&i==50)source_x=49;
   if(fault==2&&i==50)source_x=51;
   if(fault==4&&i==50)source_done=1;
   if(fault==6&&(i%997==0))begin @(negedge clk);source_start=0;source_valid=0;end
  end
  @(negedge clk);source_start=0;source_valid=0;source_done=(fault==6);source_error=0;
  @(negedge clk);source_done=0;
 end endtask
 task await_result(input[7:0]expected);integer wait_count;begin
  wait_count=0;while(results==0&&wait_count<410000)begin @(negedge clk);wait_count=wait_count+1;end
  check(results==1,"exactly one result");check(last_status==expected,"result status");
  repeat(5)@(negedge clk);check(!busy,"released ownership");
  $display("PASS case mode=%0d status=%02x writes=%0d",mode,last_status,writes);
 end endtask
 initial begin
  reset_case(0);@(negedge clk);source_start=1;@(negedge clk);source_start=0;
  check(busy,"start must acquire capture ownership");
  reset_case(0);send_frame(0,1);
  @(negedge clk);source_start=1;@(negedge clk);source_start=0;
  await_result(0);check(chars==2&&last_completed==2&&last_text[15:0]==16'h3333&&last_text[511:16]==0,"two-character result");
  check(skipped_frames==1&&frame_id==1&&completed_frames==1,"skip counters and stable accepted ID");
  reset_case(1);send_frame(0,0);await_result(0);check(last_completed==0&&norm_starts==0,"empty segmentation");
  reset_case(1);send_frame(6,1);await_result(0);
  reset_case(2);send_frame(0,0);await_result(8'h10);
  reset_case(3);send_frame(0,0);await_result(8'h11);
  reset_case(4);send_frame(0,0);await_result(8'h20);
  reset_case(5);send_frame(0,0);await_result(8'h21);
  reset_case(6);send_frame(0,0);await_result(8'h30);
  reset_case(7);send_frame(0,0);await_result(8'h30);
  reset_case(8);send_frame(0,0);await_result(8'h31);
  reset_case(10);send_frame(0,0);await_result(8'h12);
  reset_case(11);send_frame(0,0);await_result(8'h22);
  reset_case(12);send_frame(0,0);await_result(8'h22);
  reset_case(13);send_frame(0,0);await_result(8'h30);
  reset_case(14);send_frame(0,0);await_result(8'h12);
  reset_case(1);send_frame(1,0);await_result(8'h01);check(aborts==1&&cap_ends==0&&bad_captures==1,"duplicate source abort");
  // 不复位，下一帧应可恢复；坏帧期间零散像素不允许触发任务。
  results=0;writes=0;send_frame(0,0);await_result(0);check(frame_id==2&&completed_frames==1,"recovery next source frame");
  reset_case(1);send_frame(2,0);await_result(8'h01);
  reset_case(1);send_frame(3,0);await_result(8'h02);
  reset_case(1);send_frame(4,0);await_result(8'h01);
  reset_case(1);send_frame(5,0);await_result(8'h01);
  reset_case(1);@(negedge clk);source_start=1;@(negedge clk);source_start=0;await_result(8'h02);
  reset_case(0);@(negedge clk);source_start=1;@(negedge clk);source_start=0;repeat(10)@(negedge clk);
  rst=1;repeat(3)@(negedge clk);check(!busy&&!frame_we&&worker_reset,"reset aborts capture");
  reset_case(3);send_frame(0,0);wait(seg_busy);@(negedge clk);rst=1;repeat(4)@(negedge clk);
  check(!busy&&!seg_start&&worker_reset,"reset aborts segmenter");
  reset_case(5);send_frame(0,0);wait(norm_busy);@(negedge clk);rst=1;repeat(4)@(negedge clk);
  check(!busy&&!core_in_we&&worker_reset,"reset aborts normalizer");
  reset_case(8);send_frame(0,0);wait(core_busy);@(negedge clk);rst=1;repeat(4)@(negedge clk);
  check(!busy&&!core_start&&worker_reset,"reset aborts CNN");
  reset_case(1);send_frame(0,0);await_result(0);check(completed_frames==1,"recovery after stage resets");
  $display("PASS ALL plate_auto_controller");$finish;
 end
 initial begin #150000000;$fatal(1,"global simulation timeout");end
endmodule




