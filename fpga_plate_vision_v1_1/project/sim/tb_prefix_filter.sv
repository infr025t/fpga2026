`timescale 1ns/1ps
module tb_prefix_filter;
 wire split_touching=1'b0;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,skip_prefix=0;reg[7:0]roi_x0=0,roi_y0=20,roi_x1=80,roi_y1=70;reg[1:0]flags=0;
 wire busy,done,box_we;wire[7:0]error,box_x,box_y,box_w,box_h;wire[31:0]cycles;
 wire[14:0]frame_read_addr;reg[7:0]frame_read_data;wire[5:0]box_index;wire[6:0]box_count;
 reg[7:0]mem[0:19199];integer left=0,seen=0,expected_count=0;
 char_segmenter #(.ENABLE_PREFIX(1)) dut(.*);
 always @(posedge clk)frame_read_data<=mem[frame_read_addr];
 always @(negedge clk)if(box_we)begin
  if(box_index!==seen[5:0]||box_y!=30||box_h!=20)$fatal(1,"box index/height");
  if(expected_count==3&&seen==0)begin if(box_x!=left+2||box_w!=3)$fatal(1,"manual first candidate");end
  else if(seen==(expected_count==3?1:0))begin if(box_x!=left+16||box_w!=5)$fatal(1,"first letter removed");end
  else if(box_x!=left+35||box_w!=5)$fatal(1,"second letter");
  seen=seen+1;
 end
 task run_case(input integer l,input bit skip);integer i,x,y;begin
  @(negedge clk);rst=1;left=l;seen=0;expected_count=skip?2:3;
  for(i=0;i<19200;i=i+1)mem[i]=230;
  for(y=30;y<50;y=y+1)begin
   for(x=l+2;x<l+5;x=x+1)mem[y*160+x]=0;
   for(x=l+16;x<l+21;x=x+1)mem[y*160+x]=0;
   for(x=l+35;x<l+40;x=x+1)mem[y*160+x]=0;
  end
  repeat(3)@(negedge clk);rst=0;roi_x0=l;roi_x1=l+80;skip_prefix=skip;start=1;
  @(negedge clk);start=0;skip_prefix=!skip;
  wait(done);#1;if(error||box_count!=expected_count||seen!=expected_count)$fatal(1,"count/status");
  $display("PASS prefix left=%0d enabled=%0d boxes=%0d",l,skip,seen);
 end endtask
 initial begin run_case(0,0);run_case(0,1);run_case(30,1);run_case(70,1);
  $display("PASS ALL prefix RTL: relative location, retained letters, disabled mode, latched policy");$finish;end
 initial begin #300000000;$fatal(1,"timeout");end
endmodule
