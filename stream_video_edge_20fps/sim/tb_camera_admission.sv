`timescale 1ns/1ps
module tb_camera_admission;
 reg clk=0;always #5 clk=~clk;
 reg[15:0]sw=16'h0001;
 wire[7:0]ld;wire cs,rs,wr,rd,lr,bl,cr,rr,rst,wren;wire[15:0]led;
 tri sioc,siod,camrst;
 lcd_top dut(.clk100(clk),.btnC(1'b0),.sw(sw),.cam_data(8'd0),.cam_vsync(1'b1),.cam_href(1'b0),
 .cam_sioc(sioc),.cam_siod(siod),.cam_rst_n(camrst),.cam_wrst_n(rst),.cam_rclk(cr),.cam_rrst_n(rr),.cam_wen(wren),
 .lcd_data(ld),.lcd_cs_n(cs),.lcd_rs(rs),.lcd_wr_n(wr),.lcd_rd_n(rd),.lcd_reset_n(lr),.lcd_bl(bl),.led(led));
 defparam dut.display.W=16,dut.display.H=16,dut.display.PW=16,dut.display.PH=16;
 initial begin
  for(integer trial=0;trial<2;trial=trial+1)begin
   force dut.rst=1;force dut.ss=0;force dut.sink_ready=0;force dut.camera_ready=1;
   repeat(4)@(negedge clk);release dut.rst;
   wait(!dut.rst);wait(dut.display.state==3);
   @(negedge clk);release dut.sink_ready;
   wait(dut.start);@(negedge clk);
   if(dut.active_internal)$fatal(1,"camera admission precondition");
   if(trial==0)force dut.ss=16'h8000;else force dut.ss=16'h0001;
   @(negedge clk);
   if(!dut.cap_busy)$fatal(1,"issued camera frame rejected by newer pause/mode trial=%0d",trial);
   if(dut.display.state!=4 && dut.display.state!=5)$fatal(1,"display lost admission");
  end
  $display("PASS tb_camera_admission issued camera frame survives newer pause/internal request");$finish;
 end
 initial begin #500000;$fatal(1,"admission timeout");end
endmodule
