`timescale 1ns/1ps
module tb_u32_div;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0;reg[31:0] numerator=0,denominator=1;
wire busy,done;wire[31:0] quotient,remainder;
u32_div dut(.*);
integer i,t;reg[31:0] a,b;
task trial(input[31:0] x,input[31:0] y);
 begin
  @(negedge clk);numerator=x;denominator=y;start=1;
  @(negedge clk);start=0;t=0;
  while(!done&&t<40)begin @(negedge clk);t=t+1;end
  if(!done||busy||t!=32)$fatal(1,"bad divider latency t=%0d",t);
  if(y!=0)begin if(quotient!==x/y||remainder!==x%y)$fatal(1,"divide %0d/%0d q=%0d r=%0d",x,y,quotient,remainder);end
  else if(quotient!==32'hffffffff||remainder!==x)$fatal(1,"divide zero contract");
  @(negedge clk);if(done)$fatal(1,"done pulse");
 end
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 trial(0,1);trial(1,1);trial(32'hffffffff,1);trial(32'hffffffff,32'hffffffff);trial(32'hffffffff,32'h80000000);trial(32'h80000000,32'hffffffff);trial(32'h12345678,0);
 for(i=0;i<200;i=i+1)begin a=$random;b=$random;trial(a,b);end
 @(negedge clk);numerator=100;denominator=3;start=1;@(negedge clk);start=0;repeat(9)@(negedge clk);rst=1;@(negedge clk);if(busy||done)$fatal(1,"reset abort");rst=0;trial(100,3);
 $display("PASS ALL divider 208 cases, exact32-cycle latency, reset/restart");$finish;
end
endmodule
