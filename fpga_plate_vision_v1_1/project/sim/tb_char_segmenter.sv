`timescale 1ns/1ps
module tb_char_segmenter;
 wire skip_prefix=1'b0;
 wire split_touching=1'b0;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0;
 reg [7:0] roi_x0=0,roi_y0=0,roi_x1=32,roi_y1=24;
 reg [1:0] flags=0;
 wire busy,done,box_we;wire [7:0] error;wire [31:0] cycles;
 wire [14:0] frame_read_addr;reg [7:0] frame_read_data;
 wire [5:0] box_index;wire [7:0] box_x,box_y,box_w,box_h;wire [6:0] box_count;
 reg [7:0] frame[0:19199];
 integer got,expect_count,expect_status,watchdog,i,x,y,tests;
 integer fd,rc,vx0,vy0,vx1,vy1,vflags,vstatus,vcount,j,mask_index;
 string manifest_path,vector_root,vector_name;
 reg expected_mask[0:19199];
 reg check_mask=0,mask_checked=0,perturb_inputs=0;
 integer last_box_cycle,clock_count=0,largest_queue=0;
 integer ex[0:63],ey[0:63],ew[0:63],eh[0:63];
 string test_name;
 char_segmenter dut(.*);
 always @(posedge clk) begin
  clock_count<=clock_count+1;
  if(frame_read_addr>=19200) $fatal(1,"Frame address out of bounds: %0d",frame_read_addr);
  frame_read_data<=frame[frame_read_addr];
 end
 always @(negedge clk) if(!rst&&box_we) begin
  if(error!=0 || !busy) $fatal(1,"box written outside successful busy operation");
  if(got>=expect_count || box_index!==got || box_x!==ex[got] || box_y!==ey[got] || box_w!==ew[got] || box_h!==eh[got])
   $fatal(1,"%s box %0d got=(%0d,%0d,%0d,%0d) expected=(%0d,%0d,%0d,%0d)",test_name,got,box_x,box_y,box_w,box_h,ex[got],ey[got],ew[got],eh[got]);
  got=got+1;
  last_box_cycle=clock_count;
 end
 always @(negedge clk) if(!rst&&busy && dut.qtail>largest_queue) largest_queue=dut.qtail;
 task run_case(input string label_name,input integer expected_status,input integer expected_count);
 begin
  test_name=label_name;expect_count=expected_count;expect_status=expected_status;got=0;watchdog=0;mask_checked=0;last_box_cycle=-1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  while(!done && watchdog<100000000) begin
   @(negedge clk);watchdog=watchdog+1;
   if(!done && !busy) $fatal(1,"busy dropped before completion");
   if(perturb_inputs && watchdog==50) begin roi_x0=250;roi_x1=0;roi_y0=250;roi_y1=0;flags=3;start=1;end
   if(perturb_inputs && watchdog==51) start=0;
   if(check_mask && !mask_checked && dut.state==8) begin
    mask_index=0;
    for(y=vy0;y<vy1;y=y+1) for(x=vx0;x<vx1;x=x+1) begin
     if(dut.mask[y*160+x]!==expected_mask[mask_index]) $fatal(1,"%s mask mismatch x=%0d y=%0d got=%0d expected=%0d",test_name,x,y,dut.mask[y*160+x],expected_mask[mask_index]);
     mask_index=mask_index+1;
    end
    mask_checked=1;
   end
  end
  if(!done) $fatal(1,"%s watchdog",test_name);
  if(busy || error!==expect_status || box_count!==expect_count || got!=expect_count)
   $fatal(1,"%s completion got status=%0d count=%0d emitted=%0d expected status=%0d count=%0d",test_name,error,box_count,got,expect_status,expect_count);
  if(check_mask && expected_status!=1 && !mask_checked) $fatal(1,"%s threshold stage was not observed",test_name);
  if(last_box_cycle>=0 && clock_count!=last_box_cycle+1) $fatal(1,"done must be one cycle after final box");
  $display("PASS case=%s cycles=%0d count=%0d",test_name,cycles,box_count);tests=tests+1;
  @(negedge clk);if(done || box_we) $fatal(1,"done/box_we must pulse");
 end endtask
 initial begin
  tests=0;got=0;expect_count=0;
  for(i=0;i<19200;i=i+1) frame[i]=255;
  repeat(4) @(negedge clk);rst=0;
  for(y=5;y<17;y=y+1) begin
   for(x=6;x<9;x=x+1) frame[y*160+x]=0;
   for(x=20;x<24;x=x+1) frame[y*160+x]=0;
  end
  ex[0]=6;ey[0]=5;ew[0]=3;eh[0]=12;ex[1]=20;ey[1]=5;ew[1]=4;eh[1]=12;
  perturb_inputs=1;run_case("two_hand_derived_bars_busy_latch",0,2);perturb_inputs=0;
  roi_x0=0;roi_y0=0;roi_x1=32;roi_y1=24;flags=0;
  for(i=0;i<19200;i=i+1) frame[i]=255;
  run_case("blank_after_nonempty",0,0);
  roi_x1=0;run_case("zero_width",1,0);
  roi_x1=161;run_case("right_out_of_bounds",1,0);
  roi_x0=2;roi_x1=1;run_case("reversed_width",1,0);
  roi_x0=0;roi_x1=1;roi_y0=1;roi_y1=1;run_case("zero_height",1,0);
  roi_y0=0;roi_y1=121;run_case("bottom_out_of_bounds",1,0);
  // Reset aborts thresholding; the next complete ROI overwrites every mask bit.
  roi_x1=32;roi_y1=24;
  @(negedge clk);start=1;@(negedge clk);start=0;
  repeat(100) @(negedge clk);
  rst=1;@(negedge clk);rst=0;
  if(busy || done || box_we || error || box_count) $fatal(1,"reset did not abort active request");
  run_case("restart_after_mid_threshold_reset",0,0);
  if($value$plusargs("MANIFEST=%s",manifest_path)) begin
   if(!$value$plusargs("VECTOR_ROOT=%s",vector_root)) $fatal(1,"VECTOR_ROOT missing");
   fd=$fopen(manifest_path,"r");if(!fd) $fatal(1,"cannot open manifest %s",manifest_path);
   while(!$feof(fd)) begin
    rc=$fscanf(fd,"%s %d %d %d %d %d %d %d",vector_name,vx0,vy0,vx1,vy1,vflags,vstatus,vcount);
    if(rc==8) begin
     for(j=0;j<vcount;j=j+1) begin
      rc=$fscanf(fd,"%d %d %d %d",ex[j],ey[j],ew[j],eh[j]);
      if(rc!=4) $fatal(1,"invalid manifest box");
     end
     $readmemh({vector_root,"/",vector_name,".frame.mem"},frame,0,19199);
     if(vstatus!=1) $readmemh({vector_root,"/",vector_name,".mask.mem"},expected_mask,0,(vx1-vx0)*(vy1-vy0)-1);
     roi_x0=vx0;roi_y0=vy0;roi_x1=vx1;roi_y1=vy1;flags=vflags;check_mask=(vstatus!=1);
     run_case(vector_name,vstatus,vcount);check_mask=0;
    end else if(rc!=-1) $fatal(1,"invalid manifest header rc=%0d",rc);
   end
   $fclose(fd);
  end
  // Injected mask is an isolated queue-capacity stress, not an end-to-end image.
  // A uniform all-foreground mask cannot be produced by adaptive mean minus 12.
  roi_x0=0;roi_y0=0;roi_x1=160;roi_y1=120;flags=0;
  test_name="injected_full_foreground_queue";expect_count=0;got=0;largest_queue=0;
  @(negedge clk);start=1;@(negedge clk);start=0;
  while(dut.state!=2) @(negedge clk);
  force dut.state=6'd8;
  for(i=0;i<19200;i=i+1) dut.mask[i]=1;
  @(negedge clk);release dut.state;
  watchdog=0;
  while(!done && watchdog<1000000) begin @(negedge clk);watchdog=watchdog+1;end
  if(!done || error || box_count || got || largest_queue!=19200) $fatal(1,"full queue failure max=%0d error=%0d count=%0d",largest_queue,error,box_count);
  $display("PASS case=injected_full_foreground_queue max=%0d cycles=%0d",largest_queue,cycles);tests=tests+1;
  @(negedge clk);
  // Queue overflow is unreachable for a legal 19200-pixel mask; explicitly
  // corrupt the tail to verify the guard reports error 2 without any boxes.
  test_name="injected_queue_overflow";expect_count=0;got=0;
  start=1;@(negedge clk);start=0;
  while(dut.state!=2) @(negedge clk);
  force dut.state=6'd8;
  for(i=0;i<19200;i=i+1) dut.mask[i]=1;
  @(negedge clk);release dut.state;
  while(!(dut.state==16 && dut.mask_q==1)) @(negedge clk);
  force dut.qtail=16'd19200;
  @(negedge clk);release dut.qtail;
  while(!done) @(negedge clk);
  if(error!=2 || box_count || got || busy) $fatal(1,"queue overflow guard failed");
  $display("PASS case=injected_queue_overflow");tests=tests+1;
  @(negedge clk);
  test_name="reset_mid_flood";got=0;start=1;@(negedge clk);start=0;
  while(dut.state!=2) @(negedge clk);
  force dut.state=6'd8;
  for(i=0;i<19200;i=i+1) dut.mask[i]=1;
  @(negedge clk);release dut.state;
  while(dut.qhead<17) @(negedge clk);
  rst=1;@(negedge clk);rst=0;
  if(busy || done || box_we || error || box_count) $fatal(1,"reset did not abort flood fill");
  for(i=0;i<19200;i=i+1) frame[i]=255;
  roi_x1=32;roi_y1=24;
  run_case("restart_after_mid_flood_reset",0,0);
  $display("PASS tb_char_segmenter tests=%0d",tests);$finish;
 end
endmodule
