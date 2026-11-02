`timescale 1ns/1ps
// 与基线逐周期比较提取出的驱动/测试图；启动计数缩短，状态转移不变。
module tb_engineering_controls;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scene_request=1,config_done=0,config_error=0,start=0,enable=0;
 wire camera_reset_low,config_reset,camera_ready,config_scene;
 camera_startup #(.RESET_CYCLES(7),.CONFIG_CYCLES(13),.WARMUP_CYCLES(17)) startup(.*);
 reg[21:0]power_count=0;reg[27:0]warmup=0;reg ref_scene=1;
 always @(posedge clk)begin
  if(rst)begin power_count<=0;warmup<=0;ref_scene<=1;end
  else begin
   if(power_count<13)power_count<=power_count+1'b1;
   if(power_count<7)ref_scene<=scene_request;
   if(!config_done)warmup<=0;else if(warmup<17)warmup<=warmup+1'b1;
  end
 end
 wire busy,valid,done;wire[7:0]pixel;wire[9:0]x;wire[8:0]y;
 test_pattern_source source(.*);
 reg rb=0,rv=0,rd=0,ep=0;reg[6:0]cd=0;reg[9:0]px=0,ox=0;reg[8:0]py=0,oy=0;reg[7:0]pp=0;
 always @(posedge clk)begin
  rv<=0;rd<=0;
  if(rst)begin rb<=0;ep<=0;cd<=0;px<=0;py<=0;ox<=0;oy<=0;pp<=0;end
  else if(start)begin rb<=enable;ep<=0;cd<=0;px<=0;py<=0;end
  else begin
   if(ep)begin rd<=1;ep<=0;end
   if(rb)begin
    if(cd!=0)cd<=cd-1'b1;
    else begin
     cd<=11;rv<=1;pp<=(px+3*py+7)^(px>>3);ox<=px;oy<=py;
     if(px==639)begin px<=0;if(py==479)begin rb<=0;ep<=1;end else py<=py+1'b1;end
     else px<=px+1'b1;
    end
   end
  end
 end
 always @(posedge clk)begin #1;
  if({camera_reset_low,config_reset,camera_ready,config_scene}!=={(rst||power_count<7),(rst||power_count<13),(config_done&&!config_error&&warmup==17),ref_scene})$fatal(1,"startup equivalence");
  if({busy,valid,done,pixel,x,y}!=={rb,rv,rd,pp,ox,oy})$fatal(1,"pattern cycle equivalence");
 end
 reg edge_switch=0,recognition_switch=0;wire edge_requested,recognition_enabled;wire[1:0]mode;
 display_mode_control modes(.*);
 integer pixels=0;reg full_frame=0;reg[31:0]crc=32'hffffffff;
 function automatic[31:0]crc_byte(input[31:0]c,input[7:0]b);
 reg[31:0]v;begin v=c^b;for(integer k=0;k<8;k=k+1)v=(v>>1)^(v[0]?32'hedb88320:0);crc_byte=v;end endfunction
 always @(negedge clk)if(full_frame&&valid)begin
  if(x!=pixels%640||y!=pixels/640)$fatal(1,"VGA coordinates");
  crc=crc_byte(crc,pixel);pixels=pixels+1;
 end
 initial begin
  repeat(3)@(negedge clk);rst=0;scene_request=0;
  repeat(10)@(negedge clk);scene_request=1;config_done=1;
  repeat(25)@(negedge clk);if(!camera_ready||config_scene)$fatal(1,"startup readiness/scene latch");
  config_error=1;#1;if(camera_ready)$fatal(1,"configuration error guard");config_error=0;
  config_done=0;@(negedge clk);config_done=1;repeat(18)@(negedge clk);
  for(integer i=0;i<4;i=i+1)begin
   {recognition_switch,edge_switch}=i;#1;
   if(mode!=(i>=2?2:i)||recognition_enabled!=(i>=2)||edge_requested!=(i==1))$fatal(1,"mode map");
  end
  start=1;enable=0;@(negedge clk);start=0;repeat(20)@(negedge clk);if(busy||valid)$fatal(1,"disabled source");
  enable=1;start=1;@(negedge clk);start=0;repeat(35)@(negedge clk);rst=1;
  @(negedge clk);rst=0;repeat(3)@(negedge clk);full_frame=1;start=1;
  @(negedge clk);start=0;enable=0; // 已接纳帧不受请求变化影响。
  wait(done);@(negedge clk);
  if(pixels!=307200||~crc!=32'hf9824a15)$fatal(1,"VGA length/CRC");
  $display("PASS engineering controls: startup cycle equivalence, mode priority, reset/abort, full VGA CRC");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
