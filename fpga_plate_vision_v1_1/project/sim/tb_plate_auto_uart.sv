`timescale 1ns/1ps
module tb_plate_auto_uart;
 wire[7:0]seg_roi_x0=0,seg_roi_y0=0,seg_roi_x1=160,seg_roi_y1=120;
 reg clk=0; always #5 clk=~clk;
 reg rst=1;
 reg cap_begin=0,cap_end=0,cap_abort=0,seg_event=0,char_begin=0,char_event=0,result_event=0;
 reg [31:0] frame_id=1,capture_tick=123,raw_crc=0;
 reg [7:0] roi_x0=26,roi_y0=35,roi_x1=158,roi_y1=87;
 reg [1:0] flags=0;
 reg frame_we=0;reg [14:0] frame_addr=0;reg [7:0] frame_data=0;
 reg [2047:0] boxes_flat=0; reg [6:0] box_count=2;
 reg [7:0] seg_status=0;reg [31:0] seg_elapsed=1234;
 reg [5:0] char_index=0; reg [31:0] char_box=32'h180c231a;
 reg norm_pixel_we=0;reg [9:0] norm_pixel_addr=0;reg [7:0] norm_pixel_data=0;
 reg norm_done=0;reg [31:0] norm_cycles=4567;
 reg score_valid=0;reg [5:0] score_index=0;reg signed [31:0] score_data=0;
 reg [5:0] best_index=35;reg [7:0] best_ascii="Z";
 reg [31:0] norm_elapsed=4567,core_elapsed=8901;
 reg [7:0] result_status=0;reg [6:0] completed_chars=2;
 reg [511:0] text_flat=16'h5a5a;reg [31:0] elapsed_cycles=20000,bad_captures=0,skipped_frames=2;
 wire uart_txd; wire [31:0] dropped,packets;
 reg saw_reserved_overflow=0;
 plate_auto_uart dut(.*);
 always @(posedge clk)if(!rst&&dut.fault)$display("DROP t=%0t kind=%0d pos=%0d fifo=%0d",$time,dut.kind,dut.pos,dut.used);
 // 寄存级也占用预留容量；满FIFO旁边不得藏一个尚未计数的有效字节。
 always @(posedge clk)begin
  if(!rst && dut.fault && dut.stage_valid && dut.used==2047)saw_reserved_overflow<=1;
  #1;if(!rst && ({1'b0,dut.used}+dut.stage_valid)>2048)$fatal(1,"FIFO reservation overflow");
 end
 integer fd,i,j;reg [7:0] rx;reg [31:0] crc;
 function automatic [31:0] crcbyte(input [31:0] c,input [7:0] b);
 reg [31:0] v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=(v>>1)^(v[0]?32'hedb88320:0);crcbyte=v;end endfunction
 initial begin
  fd=$fopen("uart_bytes.hex","w");
  forever begin
   @(negedge uart_txd); #125;
   for(j=0;j<8;j=j+1)begin rx[j]=uart_txd;#83.333333;end
   if(uart_txd!==1'b1)$fatal(1,"UART stop bit");
   $fwrite(fd,"%02x\n",rx);
  end
 end
 task tick;begin @(posedge clk);#1;end endtask
 task idle(input integer n);integer k;begin for(k=0;k<n;k=k+1)tick();end endtask
 task result_send(input [31:0] id);begin frame_id=id;result_event=1;tick();result_event=0;idle(12000);end endtask
 initial begin
  idle(5);rst=0;idle(3);
  // 真实串口逐字节验证；首像素仅比 cap_begin 晚4拍。
  cap_begin=1;tick();cap_begin=0;idle(3);crc=32'hffffffff;
  for(i=0;i<19200;i=i+1)begin frame_we=1;frame_addr=i;frame_data=i;crc=crcbyte(crc,i);tick();frame_we=0;idle(99);end
  raw_crc=~crc;cap_end=1;tick();cap_end=0;idle(4000);
  boxes_flat[31:0]=char_box;boxes_flat[63:32]=32'h180c232a;seg_event=1;tick();seg_event=0;char_begin=1;tick();char_begin=0;idle(350);
  for(i=0;i<768;i=i+1)begin norm_pixel_we=1;norm_pixel_addr=i;norm_pixel_data=i*3;tick();norm_pixel_we=0;idle(1);end
  norm_done=1;tick();norm_done=0;
  for(i=0;i<36;i=i+1)begin score_valid=1;score_index=i;score_data=i-100;tick();end
  score_valid=0;tick();char_event=1;tick();char_event=0;
  // 前一字符尾部尚未排完时，下一char_begin不能破坏前一字符元数据。
  char_index=1;char_box=32'h180c232a;char_begin=1;tick();char_begin=0;idle(20000);
  for(i=0;i<768;i=i+1)begin norm_pixel_we=1;norm_pixel_addr=i;norm_pixel_data=i*3+1;tick();norm_pixel_we=0;idle(1);end
  norm_done=1;tick();norm_done=0;
  for(i=0;i<36;i=i+1)begin score_valid=1;score_index=i;score_data=i-200;tick();end
  score_valid=0;tick();char_event=1;tick();char_event=0;result_event=1;tick();result_event=0;idle(220000);
  if(dropped!=0||packets!=5)$fatal(1,"normal packet counts %d %d",dropped,packets);
  // EOF无效：已发前缀必须无法通过CRC；后续短包仍能重新同步。
  frame_id=2;cap_begin=1;tick();cap_begin=0;idle(30);
  for(i=0;i<10;i=i+1)begin frame_we=1;frame_addr=i;frame_data=i;tick();frame_we=0;idle(100);end
  cap_abort=1;tick();cap_abort=0;idle(5000);result_send(3);
  // 满速采集造成FIFO溢出，不能影响输入；后续结果包恢复。
  frame_id=4;cap_begin=1;tick();cap_begin=0;idle(3);
  for(i=0;i<19200;i=i+1)begin frame_we=1;frame_addr=i;frame_data=i;tick();frame_we=0;idle(3);end
  cap_end=1;tick();cap_end=0;idle(250000);result_send(5);
  // pending同类事件重入应丢包计数。
  frame_id=6;seg_event=1;tick();seg_event=0;char_begin=1;tick();char_begin=0;tick();char_begin=1;tick();char_begin=0;idle(250000);result_send(7);
  // normalizer异常中途结束，必须丢弃ACR但仍发出非零状态的结果包。
  frame_id=8;char_begin=1;tick();char_begin=0;idle(30);
  norm_pixel_we=1;norm_pixel_addr=0;norm_pixel_data=3;tick();norm_pixel_we=0;
  result_status=1;completed_chars=0;text_flat=0;result_send(8);
  // 假cap_end不能使短帧获得合法尾部。
  frame_id=9;cap_begin=1;tick();cap_begin=0;idle(30);cap_end=1;tick();cap_end=0;idle(5000);
  result_status=0;result_send(10);
  // 连续元数据包逼近满FIFO：第2048个槽已由寄存级预留，不能多接一个字节。
  frame_id=11;
  for(i=0;i<8;i=i+1)begin seg_event=1;tick();seg_event=0;idle(300);end
  idle(250000);result_send(12);
  if(!saw_reserved_overflow)$fatal(1,"registered-byte reservation boundary not exercised");
  if(dropped!=6 || packets!=18)$fatal(1,"final counts drops=%0d packets=%0d",dropped,packets);
  $display("PASS ALL auto UART packets=%0d dropped=%0d",packets,dropped);$fclose(fd);$finish;
 end
 initial begin #100000000;$fatal(1,"test timeout");end
endmodule
