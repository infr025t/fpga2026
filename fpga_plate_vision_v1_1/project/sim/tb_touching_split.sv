`timescale 1ns/1ps
module tb_touching_split;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,skip_prefix=0,split_touching=0;
 reg[7:0]roi_x0=0,roi_y0=0,roi_x1=160,roi_y1=120;reg[1:0]flags=0;
 wire busy,done,box_we;wire[7:0]error,box_x,box_y,box_w,box_h;wire[31:0]cycles;
 wire[14:0]frame_read_addr;reg[7:0]frame_read_data;wire[5:0]box_index;wire[6:0]box_count;
 reg[7:0]frame[0:19199];integer fd,rc,seen=0,expected,es,i,tests=0,x0,y0,x1,y1,fl,pr,sp;
 integer ex[0:63],ey[0:63],ew[0:63],eh[0:63];string label_name;
 char_segmenter #(.ENABLE_PREFIX(1),.ENABLE_SPLIT(1)) dut(.*);
 always @(posedge clk)begin
  if(frame_read_addr>=19200)$fatal(1,"frame address");
  frame_read_data<=frame[frame_read_addr];
 end
 always @(negedge clk)if(!rst&&box_we)begin
  if(seen>=expected||box_index!=seen||box_x!=ex[seen]||box_y!=ey[seen]||box_w!=ew[seen]||box_h!=eh[seen])
   $fatal(1,"%s box %0d got %0d,%0d,%0d,%0d expected %0d,%0d,%0d,%0d",label_name,seen,box_x,box_y,box_w,box_h,ex[seen],ey[seen],ew[seen],eh[seen]);
  seen=seen+1;
 end
 initial begin
  fd=$fopen("manifest.txt","r");if(!fd)$fatal(1,"manifest");
  repeat(4)@(negedge clk);rst=0;
  while(!$feof(fd))begin
   rc=$fscanf(fd,"%s %d %d %d %d %d %d %d %d %d",label_name,x0,y0,x1,y1,fl,pr,sp,es,expected);
   if(rc==10)begin
    for(i=0;i<expected;i=i+1)begin rc=$fscanf(fd,"%d %d %d %d",ex[i],ey[i],ew[i],eh[i]);if(rc!=4)$fatal(1,"box record");end
    $readmemh({label_name,".hex"},frame);seen=0;
    @(negedge clk);roi_x0=x0;roi_y0=y0;roi_x1=x1;roi_y1=y1;flags=fl;skip_prefix=pr;split_touching=sp;start=1;
    @(negedge clk);start=0;split_touching=!sp;skip_prefix=!pr;
    wait(done);#1;if(error!=es||box_count!=expected||seen!=expected)$fatal(1,"count/status");
    $display("PASS split %s boxes=%0d cycles=%0d",label_name,seen,cycles);tests=tests+1;
    @(negedge clk);
   end
  end
  // 在新增直方图状态中复位；下一次空图不得带入旧域或旧计数。
  $readmemh("real_1.hex",frame);@(negedge clk);roi_x0=7;roi_y0=67;roi_x1=156;roi_y1=107;flags=0;skip_prefix=1;split_touching=1;start=1;
  @(negedge clk);start=0;wait(dut.state==55);@(negedge clk);rst=1;
  @(negedge clk);rst=0;for(i=0;i<19200;i=i+1)frame[i]=97;
  expected=0;seen=0;@(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);#1;if(error||box_count||seen)$fatal(1,"reset recovery");
  // 在两框原子接纳边界注入候选占用，验证64个上限不会绕回0覆盖旧框。
  @(negedge clk);$readmemh("real_1.hex",frame);start=1;
  @(negedge clk);start=0;wait(dut.state==68);force dut.candidate_count=7'd63;
  @(posedge clk);@(negedge clk);release dut.candidate_count;
  wait(done);#1;if(error!=3||box_count||seen)$fatal(1,"two-box overflow guard");
  @(negedge clk);start=1;@(negedge clk);start=0;wait(dut.state==68);force dut.candidate_count=7'd62;
  @(posedge clk);@(negedge clk);release dut.candidate_count;wait(dut.state==20);#1;
  if(dut.candidate_count!=64)$fatal(1,"capacity boundary count");
  @(negedge clk);rst=1;@(negedge clk);rst=0;
  if(tests!=12)$fatal(1,"case count");
  $display("PASS ALL touching split RTL: 12 vectors, latched policy, reset recovery, two-box capacity");$finish;
 end
 initial begin repeat(3)#1000000000;$fatal(1,"timeout");end
endmodule
