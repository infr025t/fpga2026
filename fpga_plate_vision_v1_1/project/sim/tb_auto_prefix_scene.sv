`timescale 1ns/1ps
// 下移实拍图从相机接口输入；ROI由板上定位得到，空帧不得沿用旧框。
module tb_auto_prefix_scene;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,manual=0,diagnostic=0,ss=0,sv=0,sd=0,se=0;
 reg[7:0]sp=0;reg[9:0]sx=0;reg[8:0]sy=0;
 wire tx;wire[127:0]status;
 plate_recognition_subsystem #(.AUTO_LOCATE(1),.SKIP_CHINESE(1),.ROI_X0(0),.ROI_Y0(0),.ROI_X1(160),.ROI_Y1(120)) dut(.clk(clk),.rst(rst),.recognition_enable(1'b1),.white_characters(1'b0),.manual_mode(manual),.diagnostic_mode(diagnostic),.uart_rxd(1'b1),
  .source_start(ss),.source_valid(sv),.source_done(sd),.source_error(se),.source_pixel(sp),.source_x(sx),.source_y(sy),.uart_txd(tx),.status(status));
 reg[7:0]frame[0:19199],pixels[0:4607],ascii_expected[0:5];
 reg[31:0]scores[0:215],boxes[0:5];
 integer completed=0,char_no=0,norm_pixels=0,score_count=0,frame_writes=0;
 integer captures=0,packets=0,wire_fd,source_frame=0;reg send_blank=0,active_blank=0;
 reg[7:0]sampled;
 always @(posedge clk)if(!rst)begin
  if(dut.sb&&dut.nb || dut.sb&&dut.cb || dut.nb&&dut.cb)$fatal(1,"workers overlap");
  if(dut.a_reset && captures>0)$fatal(1,"unexpected autonomous worker reset");
  if(dut.cap_begin)begin frame_writes=0;captures=captures+1;end
  if(dut.a_fw)begin
   if(dut.a_fa!==frame_writes[14:0] || dut.a_fd!==(completed==0?frame[frame_writes]:8'd97))$fatal(1,"capture mismatch addr=%0d",frame_writes);
   if(dut.sb||dut.nb||dut.cb)$fatal(1,"frame overwrite during recognition");
   frame_writes=frame_writes+1;
  end
  if(dut.cap_end && frame_writes!=19200)$fatal(1,"capture length");
  if(dut.seg_event)begin
   if(dut.seg_status || dut.box_count!==(completed==0?6:0))$fatal(1,"segmentation count/status");
   if(completed==0)for(integer i=0;i<6;i=i+1)if(dut.boxes_flat[i*32+:32]!==boxes[i])$fatal(1,"box %0d",i);
  end
  if(dut.char_begin)begin char_no=dut.char_index;norm_pixels=0;score_count=0;end
  if(dut.a_cwe)begin
   if(dut.a_ca!==norm_pixels[9:0]||dut.a_cd!==pixels[char_no*768+norm_pixels])$fatal(1,"normalization mismatch char=%0d pixel=%0d",char_no,norm_pixels);
   norm_pixels=norm_pixels+1;
  end
  if(dut.csv)begin
   if(dut.csi>=36 || dut.csd!==scores[char_no*36+dut.csi])$fatal(1,"score mismatch char=%0d index=%0d",char_no,dut.csi);
   score_count=score_count+1;
  end
  if(dut.char_event)begin
   if(norm_pixels!=768||score_count!=36||dut.best_ascii!==ascii_expected[char_no])$fatal(1,"character output mismatch");
  end
  if(dut.result_event)begin
   if(dut.result_status || dut.completed_chars!==(completed==0?6:0))$fatal(1,"result status/count %0d",dut.result_status);
   if(completed==0)for(integer i=0;i<6;i=i+1)if(dut.text_flat[i*8+:8]!==ascii_expected[i])$fatal(1,"text mismatch");
   if(dut.publisher_dropped)$fatal(1,"unexpected publisher drop");
   $display("RESULT frame_id=%0d chars=%0d cycles=%0d skipped=%0d",dut.frame_id,dut.completed_chars,dut.elapsed_cycles,dut.skipped_frames);
   completed=completed+1;send_blank=1;
  end
 end
 initial forever begin
  @(negedge tx);#125;
  for(integer k=0;k<8;k=k+1)begin sampled[k]=tx;#83.333333;end
  if(tx!==1)$fatal(1,"UART stop bit");$fwrite(wire_fd,"%c",sampled);
 end
 initial begin
  $readmemh("frame.hex",frame);$readmemh("pixels.hex",pixels);$readmemh("scores.hex",scores);
  $readmemh("boxes.hex",boxes);$readmemh("ascii.hex",ascii_expected);
  wire_fd=$fopen("auto_wire.bin","wb");if(!wire_fd)$fatal(1,"wire output open");
  repeat(10)@(negedge clk);rst=0;
  while(completed<2)begin
   repeat(1000)@(negedge clk);
   source_frame=source_frame+1;active_blank=send_blank;
   ss=1;@(negedge clk);ss=0;
   for(integer y=0;y<480;y=y+1)for(integer x=0;x<640;x=x+1)begin
    sv=1;sx=x;sy=y;sp=active_blank?97:frame[(y/4)*160+x/4];
    @(negedge clk);sv=0;repeat(11)@(negedge clk);
   end
   sd=1;@(negedge clk);sd=0;
  end
  repeat(100000)@(negedge clk);
  if(captures!=2 || dut.skipped_frames==0 || dut.publisher_dropped!=0)$fatal(1,"capture/skip/telemetry accounting");
  $fclose(wire_fd);$display("PASS tb_auto_prefix_scene autonomous real workers, full raster, six retained characters, blank frame, skipped source frames");$finish;
 end
 initial begin wait(!rst);repeat(5)@(negedge clk);if({dut.a_x0,dut.a_y0,dut.a_x1,dut.a_y1}!=={8'd0,8'd0,8'd160,8'd120})$fatal(1,"configured ROI must reach autonomous workers and telemetry");end
 initial begin #1000000000;$fatal(1,"overall simulation timeout");end
endmodule


