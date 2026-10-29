`timescale 1ns/1ps
module tb_camera_config;
 reg clk=0;always #5 clk=~clk;reg rst=1;
 tri1 sioc,siod;reg ack_low=0;
 assign siod=ack_low?1'b0:1'bz;
 wire done,error;

  ov7670_config #(.QUARTER_CYCLES(2),.POWER_WAIT(8),.REG_WAIT(2)) dut(
   .clk(clk),.rst(rst),.slow_clock(1'b0),.scene(1'b1),.sioc(sioc),.siod(siod),.done(done),.error(error),.scl_drive_low(),.sda_drive_low());

 integer bits=0,writes=0,cycles=0,scene_cycle=0;reg active=0;
 reg[7:0]b0=0,b1=0,b2=0,last_com8=0;integer freeze_count=0;
 always @(posedge clk)cycles<=cycles+1;
 always @(negedge siod)if(sioc&&!rst)begin active=1;bits=0;b0=0;b1=0;b2=0;end
 always @(negedge sioc)if(active)ack_low=(bits%9==8);else ack_low=0;
 always @(posedge sioc)if(active)begin
  if(bits<8)b0={b0[6:0],siod};
  else if(bits>=9&&bits<17)b1={b1[6:0],siod};
  else if(bits>=18&&bits<26)b2={b2[6:0],siod};
  bits=bits+1;
 end
 always @(posedge siod)if(sioc&&active)begin
  if(bits<27||b0!=8'h42)$fatal(1,"bad SCCB transaction bits%0d address%h",bits,b0);
  writes=writes+1;
  if(b1==8'h42)scene_cycle=cycles;
  if(b1==8'h13)begin
   last_com8=b2;
   if(b2!=8'he7)begin
    freeze_count=freeze_count+1;
    if(cycles-scene_cycle<80)$fatal(1,"AEC frozen before settling interval");
   end
  end
  active=0;
 end
 initial begin
  repeat(8)@(negedge clk);rst=0;wait(done||error);repeat(4)@(negedge clk);
  if(error)$fatal(1,"SCCB ACK failure");
  if(last_com8!=8'he7||freeze_count!=0||writes!=39)$fatal(1,"AEC/AGC must remain enabled after init COM8=%h freezes=%0d writes=%0d",last_com8,freeze_count,writes);
  repeat(200)@(negedge clk);
  if(writes!=39)$fatal(1,"unexpected runtime SCCB writes");
  $display("PASS tb_camera_config writes=%0d COM8=%h init_only",writes,last_com8);$finish;
 end
 initial begin #2000000;$fatal(1,"watchdog");end
endmodule
