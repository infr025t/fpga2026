`timescale 1ns/1ps
module tb_camera_video #(parameter ACCESS_NS=15,Y_BYTE=0,W=32,H=24,CAP=1024,HEAD=4,BYTE_NS=40,GAP_CYCLES=80,BLANK_CYCLES=2600,BEFORE=3,AFTER=3,PAUSE_CYCLES=50000);
 reg clk=0;always #5 clk=~clk;reg rst=1,start=0,pause=0,vsync=1,href=0;
 wire rclk,rrst,wrst,wen,busy,done,pv;wire[7:0]p,error,other;wire[9:0]px;wire[8:0]py;
 wire[31:0]wf,rf,sp,ml;wire[255:0]timing;
 reg[7:0]data=0,mem[0:CAP-1],pending[0:127],value=0;
 integer rp=0,written=0,committed=0,field=0,base_field=-1,epoch_reads=0,seen=0,frames=0;
 integer i,x,y,k;reg reset_pending=1,wck=0;
 camera_fifo_video #(.W(W),.H(H),.FIFO_BYTES(CAP),.HEAD_ROWS(HEAD),.PERIOD(6),.Y_BYTE(Y_BYTE)) dut(
 .clk(clk),.rst(rst),.start(start),.pause(pause),.vsync(vsync),.href(href),.data(data),
 .rclk(rclk),.rrst(rrst),.wrst(wrst),.wen(wen),.busy(busy),.done(done),.error(error),
 .pixel_valid(pv),.pixel(p),.pixel_other(other),.pixel_x(px),.pixel_y(py),.debug_timing(timing),.debug_sync(),
 .sensor_frames(wf),.read_frames(rf),.sensor_period(sp),.max_occupancy(ml));
 function automatic[7:0]pattern(input integer index,f);pattern=((index*37)^(index>>7)^19^(f*73))&255;endfunction
 always #(BYTE_NS/2.0) wck=~wck;
 always @(posedge wck)begin
  if(!wrst)reset_pending=1;
  if(wen&&href)begin
   if(reset_pending)begin written=0;committed=0;reset_pending=0;base_field=-1;epoch_reads=0;end
   if(wrst)begin
    if(base_field<0)base_field=field;
    if(written-committed==128)begin mem[committed%CAP]=pending[committed%128];committed=committed+1;end
    pending[written%128]=value;written=written+1;
   end
  end
 end
 always @(posedge rclk)begin
  if(!rrst)begin rp=1;data<=#ACCESS_NS mem[0];end
  else begin data<=#ACCESS_NS mem[rp];rp=(rp+1)%CAP;end
 end
 always @(posedge clk)if(!rst)begin
  if(error)$fatal(1,"capture error %h frames=%0d timing=%h",error,frames,timing);
  if(pv)begin
   if(p!==pattern(seen*2+Y_BYTE,base_field+epoch_reads)||px!==seen%W||py!==seen/W)
    $fatal(1,"data mismatch frame=%0d n=%0d xy=%0d,%0d value=%h wanted=%h fieldbase=%0d",frames,seen,px,py,p,pattern(seen*2+Y_BYTE,base_field+epoch_reads),base_field);
   if(seen>0 && other!==pattern(seen*2+Y_BYTE-1,base_field+epoch_reads))$fatal(1,"preceding byte mismatch frame=%0d n=%0d got=%h",frames,seen,other);
   seen=seen+1;
  end
  if(done)begin
   if(seen!=W*H)$fatal(1,"short frame %0d",seen);
   seen=0;frames=frames+1;epoch_reads=epoch_reads+1;
  end
 end
 task request_frame;
 begin @(negedge clk);start=1;@(negedge clk);start=0;wait(done);@(negedge clk);repeat(100)@(negedge clk);end
 endtask
 initial begin
  for(k=0;k<CAP;k=k+1)mem[k]=8'hdd;
  repeat(20)@(negedge clk);rst=0;
  repeat(BEFORE)request_frame();
  @(negedge clk);start=1;@(negedge clk);start=0;wait(px==W/2&&py==H/2&&pv);@(negedge clk);pause=1;
  wait(done);repeat(PAUSE_CYCLES)@(negedge clk);
  if(wen||rrst||busy)$fatal(1,"pause did not release ownership safely");
  pause=0;repeat(AFTER)request_frame();
  if(frames!=BEFORE+AFTER+1||rf!=BEFORE+AFTER+1)$fatal(1,"frame count %0d/%0d",frames,rf);
  $display("PASS tb_camera_video frames=%0d pixel_alignment wrap continuous_commit pause_resume maxlag=%0d",frames,ml);$finish;
 end
 initial begin
  repeat(5)@(negedge clk);
  forever begin
   vsync=0;href=0;repeat(BLANK_CYCLES)@(negedge clk);
   field=field+1;vsync=1;repeat(120)@(negedge clk);
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<2*W;x=x+1)begin @(negedge wck);href=1;value=pattern(y*2*W+x,field);end
    @(negedge wck);href=0;repeat(GAP_CYCLES)@(negedge clk);
   end
  end
 end
 initial begin #2000000000;$fatal(1,"timeout frames=%0d state=%0d",frames,dut.ws);end
endmodule
