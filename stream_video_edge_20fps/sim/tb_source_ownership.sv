`timescale 1ns/1ps
module tb_source_ownership;
 reg clk=0;always #5 clk=~clk;
 reg[15:0]sw=16'h0001;
 wire[7:0]ld;wire cs,rs,wr,rd,lr,bl,cr,rr,rst,wren;wire[15:0]led;
 tri sioc,siod,camrst;
 lcd_top dut(.clk100(clk),.btnC(1'b0),.sw(sw),.cam_data(8'd0),.cam_vsync(1'b1),.cam_href(1'b0),
 .cam_sioc(sioc),.cam_siod(siod),.cam_rst_n(camrst),.cam_wrst_n(rst),.cam_rclk(cr),.cam_rrst_n(rr),.cam_wen(wren),
 .lcd_data(ld),.lcd_cs_n(cs),.lcd_rs(rs),.lcd_wr_n(wr),.lcd_rd_n(rd),.lcd_reset_n(lr),.lcd_bl(bl),.led(led));
 defparam dut.display.W=16,dut.display.H=16,dut.display.PW=16,dut.display.PH=16;
 initial begin
  force dut.sink_ready=0;
  wait(!dut.rst);wait(dut.display.state==3);
  force dut.ss=16'h0001;
  force dut.inflight=0;
  force dut.cap_busy=1;
  force dut.pattern_busy=0;
  @(negedge clk);release dut.sink_ready;
  repeat(3)begin @(negedge clk);if(dut.start)$fatal(1,"next frame began before camera tail drained");end
  force dut.cap_busy=0;force dut.pattern_busy=1;
  repeat(3)begin @(negedge clk);if(dut.start)$fatal(1,"next frame began before internal source tail drained");end
  force dut.pattern_busy=0;
  @(negedge clk);if(!dut.start)$fatal(1,"source drain did not release next frame");
  $display("PASS tb_source_ownership full source frame owns tail after cropped output completes");$finish;
 end
 initial begin #500000;$fatal(1,"admission timeout");end
endmodule
