`timescale 1ns/1ps
module tb_camera_recovery;
 reg clk=0;always #5 clk=~clk;reg rst=1,start=0;
 wire rclk,rrst,wrst,wen,busy,done,pv;wire[7:0]error;
 camera_fifo_capture #(.W(64),.H(64),.FIFO_BYTES(6144),.HEAD_ROWS(4),.HREF_MIN(8),.TIMEOUT(2000)) dut(
  .clk(clk),.rst(rst),.start(start),.vsync(1'b1),.href(1'b0),.data(8'd0),
  .rclk(rclk),.rrst(rrst),.wrst(wrst),.wen(wen),.busy(busy),.done(done),.error(error),.pixel_valid(pv),
  .pixel(),.pixel_x(),.pixel_y(),.debug_read_bytes(),.debug_rows(),.debug_timing());
 initial begin
  repeat(20)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
  repeat(10)@(negedge clk);rst=1;repeat(4)@(negedge clk);rst=0;@(negedge clk);
  if(busy||wen||!wrst||pv||error)$fatal(1,"reset did not safely abort priming");
  start=1;@(negedge clk);start=0;wait(done);@(negedge clk);
  if(error!=8'h23||wen||!wrst||busy||pv)$fatal(1,"priming timeout unsafe error%h",error);
  $display("PASS tb_camera_recovery reset_abort and no_HREF_timeout");$finish;
 end
 initial begin #500000;$fatal(1,"priming has no timeout recovery");end
endmodule
