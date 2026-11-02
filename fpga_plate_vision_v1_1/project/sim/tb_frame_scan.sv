`timescale 1ns/1ps
module tb_frame_scan;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,we=0,scan_en=0;reg[14:0]addr=0,scan_addr=0;reg[7:0]data=0;
 wire[7:0]scan_data;wire busy,done,error,pwe;wire[31:0]cycles;wire[9:0]pa;wire[7:0]pd;
 char_normalizer #(.ENABLE_SCAN(1)) dut(.clk(clk),.rst(rst),.start(start),.frame_we(we),.frame_addr(addr),.frame_data(data),
  .scan_en(scan_en),.scan_addr(scan_addr),.scan_data(scan_data),
  .box_x(8'd0),.box_y(8'd0),.box_w(8'd1),.box_h(8'd1),.roi_x0(8'd0),.roi_y0(8'd0),.roi_x1(8'd1),.roi_y1(8'd1),.flags(2'd0),
  .busy(busy),.done(done),.error(error),.cycles(cycles),.pixel_we(pwe),.pixel_addr(pa),.pixel_data(pd));
 integer i;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<19200;i=i+1)begin @(negedge clk);we=1;addr=i;data=(i*13+7)&255;end
  @(negedge clk);we=0;scan_en=1;
  for(i=0;i<19200;i=i+1)begin
   @(negedge clk);scan_addr=i;
   @(posedge clk);#1;if(scan_data!==((i*13+7)&255))$fatal(1,"read bank addr%0d got%0d",i,scan_data);
  end
  @(negedge clk);scan_addr=0;we=1;addr=0;data=255;start=1;
  repeat(4)@(negedge clk);
  if(busy||done||pwe)$fatal(1,"worker started during scan ownership");
  we=0;start=0;
  @(posedge clk);#1;if(scan_data!==8'd7)$fatal(1,"upload modified scan-owned frame");
  @(negedge clk);scan_en=0;start=1;
  @(negedge clk);start=0;
  wait(done);if(error)$fatal(1,"normalizer failed after scan release");
  $display("PASS frame scan all19200 addresses, write/start exclusion, release");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
