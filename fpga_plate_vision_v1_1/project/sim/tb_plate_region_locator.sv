`timescale 1ns/1ps
module tb_plate_region_locator;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0;wire busy,done,found;wire[7:0]x0,y0,x1,y1;wire[31:0]cycles;
 wire[14:0]read_addr;reg[7:0]read_data;reg[7:0]mem[0:19199];
 always @(posedge clk)read_data<=mem[read_addr];
 plate_region_locator dut(.*);
 integer fd,rc,n,i,ef,ex0,ey0,ex1,ey1;reg[1023:0]name,path;
 initial begin
  fd=$fopen("../../sim/locator_vectors/count.txt","r");rc=$fscanf(fd,"%d",n);$fclose(fd);
  fd=$fopen("../../sim/locator_vectors/manifest.txt","r");
  for(i=0;i<n;i=i+1)begin
   rc=$fscanf(fd,"%s %d %d %d %d %d",name,ef,ex0,ey0,ex1,ey1);
   if(rc!=6)$fatal(1,"manifest");
   $sformat(path,"../../sim/locator_vectors/%0s.mem",name);$readmemh(path,mem);
   @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;start=1;
   @(negedge clk);start=0;wait(done);#1;
   if(found!==ef[0]||x0!==ex0[7:0]||y0!==ey0[7:0]||x1!==ex1[7:0]||y1!==ey1[7:0])
    $fatal(1,"ROI %0s got %0d (%0d,%0d,%0d,%0d) expected %0d (%0d,%0d,%0d,%0d)",name,found,x0,y0,x1,y1,ef,ex0,ey0,ex1,ey1);
   if(busy||cycles>120000)$fatal(1,"completion/cycle bound");
   $display("PASS locator %0s cycles=%0d",name,cycles);
  end
  // 中途复位必须取消任务并清除旧区域。
  @(negedge clk);start=1;@(negedge clk);start=0;repeat(50)@(negedge clk);rst=1;
  @(negedge clk);if(busy||found||done)$fatal(1,"reset did not cancel");
  $display("PASS ALL locator RTL %0d cases",n);$finish;
 end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
