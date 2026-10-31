`timescale 1ns/1ps
// Application-contract model, not an electrical AL422 model. Every frame has
// unique bytes;128 bytes of input are withheld until further writes/reset.
module tb_camera_capture #(parameter W=64,H=64,CAP=6144,HEAD_ROWS=4,CAPTURES=3,GLITCH_TEST=0,GLITCH_CYCLES=5,EXPECT_ERROR=0);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,vsync=1,href=0;
 reg vsync_glitch=0;wire camera_vsync=vsync&&!vsync_glitch;
 wire rclk,rrst,wrst,wen,busy,done,pv,reading,active;
 wire[7:0]pixel,error;wire[9:0]px;wire[8:0]py;
 reg[7:0]data=0,mem[0:CAP-1],pending[0:127];
 integer rp=0,wp=0,written=0,committed=0,seen=0,k,j,frame=0,x,y;
 integer expected_frame=-1,captures=0,total_seen=0;
 reg reset_pending=1,old_active=0;
 reg[7:0]value;
 function automatic[7:0]pattern(input integer i,f);pattern=((i*37)^(i>>7)^(i>>11)^19^(f*73))&255;endfunction

  camera_fifo_capture #(.W(W),.H(H),.FIFO_BYTES(CAP),.HEAD_ROWS(HEAD_ROWS),.HREF_MIN(8),.TIMEOUT(200000000)) dut(
   .clk(clk),.rst(rst),.start(start),.vsync(camera_vsync),.href(href),.data(data),.rclk(rclk),.rrst(rrst),.wrst(wrst),.wen(wen),
   .busy(busy),.done(done),.error(error),.pixel_valid(pv),.pixel(pixel),.pixel_x(px),.pixel_y(py),.debug_read_bytes(),.debug_rows(),.debug_timing());
  wire ref_rclk,ref_rrst,ref_wrst,ref_wen,ref_busy,ref_done,ref_pv;
  wire[7:0]ref_error,ref_pixel;wire[9:0]ref_x;wire[8:0]ref_y;
  camera_fifo_capture_reference #(.W(W),.H(H),.FIFO_BYTES(CAP),.HEAD_ROWS(HEAD_ROWS),.HREF_MIN(8),.TIMEOUT(200000000)) reference(
   .clk(clk),.rst(rst),.start(start),.vsync(camera_vsync),.href(href),.data(data),.rclk(ref_rclk),.rrst(ref_rrst),.wrst(ref_wrst),.wen(ref_wen),
   .busy(ref_busy),.done(ref_done),.error(ref_error),.pixel_valid(ref_pv),.pixel(ref_pixel),.pixel_x(ref_x),.pixel_y(ref_y),
   .debug_read_bytes(),.debug_rows(),.debug_timing(),.debug_sync(),.period_cycles(8'd50),
   .debug_byte_valid(),.debug_byte_index(),.debug_byte_data());
  always @(negedge clk)if(!rst && {rclk,rrst,wrst,wen,busy,done,error,pv,pixel,px,py} !==
   {ref_rclk,ref_rrst,ref_wrst,ref_wen,ref_busy,ref_done,ref_error,ref_pv,ref_pixel,ref_x,ref_y})
    $fatal(1,"consolidated capture differs from hardware-tested reference");
  assign reading=dut.rs==2;assign active=dut.state==3;

 // AL422-07: reset already prefetches byte0; first released read edge outputs byte1.
 always @(posedge rclk)begin
  if(!rrst)begin rp=1;data<=#15 mem[0];end
  else begin data<=#15 mem[rp];rp=(rp+1)%CAP;end
 end
 always @(posedge clk)if(!rst)begin
  old_active<=active;
  if(active&&!old_active)begin expected_frame=frame;seen=0;end
  if(reading&&!wrst)$fatal(1,"WRST asserted inside one selected-frame read interval");
  if(pv)begin
   if(pixel!==pattern(seen*2+1,expected_frame)||px!==seen%W||py!==seen/W)
    $fatal(1,"tag/position mismatch capture%0d pixel%0d expected_frame%0d got%h xy%0d,%0d",captures,seen,expected_frame,pixel,px,py);
   seen=seen+1;total_seen=total_seen+1;
  end
 end
 // Continuous WCK, including disabled cycles; /WE is WEN AND HREF.
 // Reset requests while /WE is disabled are deferred to the next enable.
 reg wck=0;
 integer producer_half=16;
 always begin #(producer_half*10) wck=~wck;end
 always @(posedge wck)begin
  if(!wrst)reset_pending=1;
  if(wen&&href)begin
   if(reset_pending)begin
    for(j=committed;j<written;j=j+1)mem[j%CAP]=pending[j%128];
    wp=0;written=0;committed=0;reset_pending=0;
   end
   if(wrst)begin
    if(written-committed==128)begin mem[committed%CAP]=pending[committed%128];committed=committed+1;end
    pending[written%128]=value;written=written+1;wp=(wp+1)%CAP;
   end
  end
 end
 initial begin
  for(k=0;k<CAP;k=k+1)mem[k]=8'hdd;
  repeat(20)@(negedge clk);rst=0;repeat(20)@(negedge clk);
  repeat(CAPTURES)begin
   start=1;@(negedge clk);start=0;
   wait(done);@(negedge clk);
   if(EXPECT_ERROR)begin
    if(error!=8'h21||seen>=W*H||wen||!wrst)$fatal(1,"long premature VSYNC incorrectly accepted error%h seen%0d",error,seen);
    $display("PASS tb_camera_capture long_pulse_rejected error=%h pixels=%0d",error,seen);$finish;
   end
   if(error||seen!=W*H)$fatal(1,"capture failed error%h count%0d",error,seen);
   captures=captures+1;
   repeat(100)@(negedge clk);
  end
  $display("PASS tb_camera_capture captures=%0d pixels=%0d no_midread_wrst model_only",captures,total_seen);$finish;
 end
 initial if(GLITCH_TEST)begin
  wait(active);wait(y==H/2&&href);repeat(40)@(negedge clk);
  vsync_glitch=1;repeat(GLITCH_CYCLES)@(negedge clk);vsync_glitch=0;
 end
 initial begin
  repeat(100)@(negedge clk);
  for(frame=0;frame<16;frame=frame+1)begin
   producer_half=15+frame%3;
   vsync=0;repeat(30)@(negedge wck);vsync=1;repeat(30)@(negedge wck);
   for(y=0;y<H;y=y+1)begin
    @(negedge wck);href=1;value=pattern(y*W*2,frame);
    for(x=1;x<W*2;x=x+1)begin @(negedge wck);value=pattern(y*W*2+x,frame);end
    @(negedge wck);href=0;repeat(30)@(negedge wck);
   end
  end
 end
 initial begin #5000000000;$fatal(1,"watchdog");end
endmodule

