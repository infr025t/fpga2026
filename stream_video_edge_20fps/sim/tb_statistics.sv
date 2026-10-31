`timescale 1ns/1ps
module tb_statistics;
 reg clk=0;always #5 clk=~clk;
 reg[15:0]sw=16'h0001;
 wire[7:0]ld;wire cs,rs,wr,rd,lr,bl,cr,rr,rst,wren;wire[15:0]led;
 tri sioc,siod,camrst;
 lcd_top #(.STAT_FRAMES(3)) dut(.clk100(clk),.btnC(1'b0),.sw(sw),.cam_data(8'd0),.cam_vsync(1'b1),.cam_href(1'b0),
 .cam_sioc(sioc),.cam_siod(siod),.cam_rst_n(camrst),.cam_wrst_n(rst),.cam_rclk(cr),.cam_rrst_n(rr),.cam_wen(wren),
 .lcd_data(ld),.lcd_cs_n(cs),.lcd_rs(rs),.lcd_wr_n(wr),.lcd_rd_n(rd),.lcd_reset_n(lr),.lcd_bl(bl),.led(led));
 defparam dut.display.W=16,dut.display.H=16,dut.display.PW=16,dut.display.PH=16;
 initial begin
  force dut.sink_ready=0;
  wait(!dut.rst);
  force dut.active_internal=0;force dut.active_edge=0;force dut.config_scene=0;
  force dut.sink_done=0;
  for(integer i=0;i<3;i=i+1)begin
   @(negedge clk);
   if(i==1)force dut.input_crc=32'h12345678;else force dut.input_crc=32'h6df0b9b5;
   force dut.sink_done=1;
   @(negedge clk);force dut.sink_done=0;
  end
  @(negedge clk);
  if(dut.display_frames!=3||dut.reference_failures!=1||dut.ref_fault||!dut.statistics_complete)
   $fatal(1,"statistics must continue on CRC failure and stop exactly at target frames=%0d bad=%0d fault=%0d",dut.display_frames,dut.reference_failures,dut.ref_fault);
  force dut.sink_ready=1;force dut.camera_ready=1;force dut.inflight=0;force dut.ss=0;force dut.cap_busy=0;force dut.pattern_busy=0;
  repeat(4)begin @(negedge clk);if(dut.start)$fatal(1,"started frame beyond stats target");end
  $display("PASS tb_statistics all-frame CRC counter, continuation and exact target");$finish;
 end
 initial begin #500000;$fatal(1,"admission timeout");end
endmodule
