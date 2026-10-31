`timescale 1ns/1ps
module tb_lcd_admission;
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
  @(negedge clk);sw[2]=1;
  @(negedge clk);release dut.sink_ready;
  @(negedge clk);
  if(!dut.start || dut.active_edge || !dut.ss[2])$fatal(1,"failed to exercise registered-start mode race");
  @(negedge clk);
  if(dut.display.state!=4 && dut.display.state!=5)$fatal(1,"accepted source start lost to a newer mode request; state=%0d",dut.display.state);
  $display("PASS tb_lcd_admission registered-start mode race does not lose frame ownership");$finish;
 end
 initial begin #500000;$fatal(1,"admission timeout");end
endmodule
