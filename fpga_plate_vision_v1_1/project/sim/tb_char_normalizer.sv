`timescale 1ns/1ps
module tb_char_normalizer;
reg clk=0; always #5 clk=~clk;
reg rst=1,start=0,frame_we=0;
reg [14:0] frame_addr=0; reg [7:0] frame_data=0;
reg [7:0] box_x=0,box_y=0,box_w=0,box_h=1,roi_x0=0,roi_y0=0,roi_x1=160,roi_y1=120;
reg [1:0] flags=0;
wire busy,done,error,pixel_we; wire [31:0] cycles; wire [9:0] pixel_addr; wire [7:0] pixel_data;
char_normalizer dut(.*);
reg [7:0] input_mem[0:19199],expected_mem[0:767];
integer t,i,n,count,fh,rc,iv[0:8],cases=0; string base,name,path;
task launch;
 begin @(negedge clk);start=1;@(negedge clk);start=0;end
endtask
task rejected;
 begin
  launch();t=0;
  while(!done&&t<20) begin if(pixel_we)$fatal(1,"invalid descriptor emitted pixels");@(negedge clk);t=t+1;end
  if(!done||!error||pixel_we||busy)$fatal(1,"invalid descriptor not rejected");
  @(negedge clk);if(done)$fatal(1,"done must pulse");
 end
endtask
task check_output;
 begin
  count=0;t=0;
  while(!done&&t<2000000) begin
   if(pixel_we) begin
    if(pixel_addr!==count || pixel_data!==expected_mem[count])
     $fatal(1,"case %s pixel %0d addr=%0d got=%0d expected=%0d",name,count,pixel_addr,pixel_data,expected_mem[count]);
    count=count+1;
   end
   @(negedge clk);t=t+1;
  end
  if(!done||error||busy||count!=768||pixel_we)$fatal(1,"bad completion %s count=%0d error=%b cycles=%0d",name,count,error,cycles);
  $display("PASS %s bytes=%0d cycles=%0d",name,count,cycles);
  @(negedge clk);if(done)$fatal(1,"done must be one cycle");
 end
endtask
initial begin
 base="../norm_reference/rtl_vectors";
 rc=$value$plusargs("vectors=%s",base);
 repeat(4) @(negedge clk);rst=0;
 // 错误边界：零宽、加法溢出、ROI越界、bbox超出ROI。
 rejected();box_w=255;box_x=159;rejected();box_x=0;box_w=1;roi_x1=161;rejected();roi_x1=160;roi_x0=1;rejected();roi_x0=0;roi_y1=0;rejected();roi_y1=120;
 path={base,"/manifest.txt"};fh=$fopen(path,"r");if(!fh)$fatal(1,"missing manifest %s",path);
 while(!$feof(fh)) begin
  rc=$fscanf(fh,"%s %d %d %d %d %d %d %d %d %d\n",name,iv[0],iv[1],iv[2],iv[3],iv[4],iv[5],iv[6],iv[7],iv[8]);
  if(rc==10) begin
   path={base,"/",name,".frame.mem"};$readmemh(path,input_mem);
   path={base,"/",name,".expected.mem"};$readmemh(path,expected_mem);
   for(i=0;i<19200;i=i+1) begin @(negedge clk);frame_we=1;frame_addr=i;frame_data=input_mem[i];end
   @(negedge clk);frame_we=0;
   box_x=iv[0];box_y=iv[1];box_w=iv[2];box_h=iv[3];roi_x0=iv[4];roi_y0=iv[5];roi_x1=iv[6];roi_y1=iv[7];flags=iv[8];
   // 第一例中途复位，再用相同帧重启；复位不应擦除帧RAM。
   if(cases==0) begin
    launch();repeat(500) @(negedge clk);rst=1;repeat(3) @(negedge clk);
    if(busy||done||pixel_we)$fatal(1,"reset did not abort");rst=0;
   end
   launch();
   // 忙时start/上传及外部描述符变化均不能扰动本次处理。
   frame_we=1;frame_addr=0;frame_data=~input_mem[0];start=1;
   box_w=0;box_x=255;roi_x1=0;flags=~flags;
   @(negedge clk);frame_we=0;start=0;
   check_output();cases=cases+1;
  end
 end
 $fclose(fh);if(cases<18)$fatal(1,"too few vectors: %0d",cases);
 $display("PASS ALL normalizer cases=%0d plus invalid/reset/restart/busy-write contracts",cases);$finish;
end
endmodule
