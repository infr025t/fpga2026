`timescale 1ns/1ps
module tb_roi_overlay;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,enabled=1,frame_start=0,roi_event=0,roi_valid=1;
 reg[7:0]roi_x0=0,roi_y0=0,roi_x1=160,roi_y1=120;
 reg[9:0]x=0;reg[8:0]y=0;wire border;
 plate_roi_overlay dut(.*);
 task step;begin @(posedge clk);#1;@(negedge clk);end endtask
 task commit;begin frame_start=1;step;frame_start=0;end endtask
 task point(input integer xx,yy,input bit expected);begin x=xx;y=yy;#1;if(border!==expected)$fatal(1,"border x=%0d y=%0d",xx,yy);end endtask
 initial begin
  step;rst=0;roi_event=1;step;roi_event=0;
  point(0,0,0);commit;point(0,0,1);point(639,479,1);point(2,2,0);point(640,0,0);
  enabled=0;step;point(0,0,1);commit;point(0,0,0);
  enabled=1;commit;point(0,0,0);
  roi_event=1;roi_x0=3;roi_x1=4;roi_y0=4;roi_y1=5;step;roi_event=0;commit;
  point(12,16,1);point(15,19,1);point(16,19,0);point(11,16,0);
  roi_event=1;roi_x1=161;step;roi_event=0;point(12,16,1);commit;point(12,16,0);
  roi_x1=4;roi_event=1;step;roi_event=0;commit;point(12,16,1);
  roi_event=1;roi_valid=0;step;roi_event=0;commit;point(12,16,0);
  rst=1;step;point(0,0,0);
  $display("PASS ROI bounds, half-open mapping, disable/reenter, invalid, reset, frame atomicity");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
