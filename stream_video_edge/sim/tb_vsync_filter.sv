`timescale 1ns/1ps
module tb_vsync_filter;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,clear_stats=0,din=1;wire dout;
 wire[31:0]last_long,rejected,max_short,last_raw;
 integer n,j;
 vsync_low_filter #(.MIN_LOW(64)) dut(.clk(clk),.rst(rst),.clear_stats(clear_stats),.sync_in(din),.sync_out(dout),
  .last_long_low(last_long),.rejected(rejected),.max_rejected(max_short),.last_raw_low(last_raw));
 initial begin
  repeat(5)@(negedge clk);rst=0;repeat(5)@(negedge clk);
  for(n=1;n<=128;n=n+1)begin
   din=0;
   for(j=1;j<=n;j=j+1)begin
    @(negedge clk);
    if(dout!==(j<64))$fatal(1,"low qualification wrong n%0d tick%0d out%b",n,j,dout);
   end
   din=1;@(negedge clk);
   if(dout!==1||last_raw!=n)$fatal(1,"rise delayed or pulse measurement wrong");
   if(n<64)begin if(rejected!=n||max_short!=n)$fatal(1,"short diagnostic wrong");end
   else if(last_long!=n||rejected!=63||max_short!=63)$fatal(1,"valid pulse lost or miscounted");
   repeat(2)@(negedge clk);
  end
  din=0;repeat(80)@(negedge clk);clear_stats=1;@(negedge clk);clear_stats=0;
  if(dout!==0)$fatal(1,"clearing statistics changed frame state");
  din=1;@(negedge clk);if(dout!==1)$fatal(1,"rise after clear failed");
  $display("PASS tb_vsync_filter short_lengths1_to63 valid64_to128 immediate_rise clear_preserves_state");$finish;
 end
endmodule
