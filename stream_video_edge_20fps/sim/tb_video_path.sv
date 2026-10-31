`timescale 1ns/1ps
module tb_video_path #(parameter W=32,H=24);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,source_valid=0,source_done=0,edge_view=0;
 reg[7:0]source_pixel=0;reg[9:0]source_x=0;reg[8:0]source_y=0;
 wire v,d,e;wire[7:0]p,raw;wire[9:0]x;wire[8:0]y;
 video_core_adapter #(W,H) dut(.clk(clk),.rst(rst),.start(start),.edge_view(edge_view),
 .source_valid(source_valid),.source_pixel(source_pixel),.source_x(source_x),.source_y(source_y),.source_done(source_done),
 .out_valid(v),.out_pixel(p),.out_raw(raw),.out_x(x),.out_y(y),.out_done(d),.error(e));
 reg[7:0]image[0:W*H-1],expected[0:W*H-1];reg[1023:0]folder;
 integer frame,xx,yy,n=0,ew,eh,timeout=0;reg finished=0;
 always @(posedge clk)if(!rst)begin
  if(v)begin
   if(x!==n%ew || y!==n/ew || p!==expected[n] || raw!==image[(edge_view?(n/ew+5):n/ew)*W+(edge_view?(n%ew+5):n%ew)])
    $fatal(1,"path mismatch frame=%0d n=%0d xy=%0d,%0d got=%0d ref=%0d raw=%0d",frame,n,x,y,p,expected[n],raw);
   n=n+1;
  end
  if(e)$fatal(1,"core error");
  if(d)begin if(n!=ew*eh)$fatal(1,"early done frame=%0d n=%0d",frame,n);finished=1;end
 end
 initial begin
  if(!$value$plusargs("VECTORS=%s",folder))$fatal(1,"vectors missing");
  $readmemh({folder,"/image.hex"},image);
  repeat(4)@(negedge clk);rst=0;
  for(frame=0;frame<2;frame=frame+1)begin
   edge_view=frame[0];ew=edge_view?W-10:W;eh=edge_view?H-10:H;
   if(!edge_view)$readmemh({folder,"/image.hex"},expected);
   else $readmemh({folder,"/edge_1.hex"},expected,0,(W-10)*(H-10)-1);
   n=0;finished=0;start=1;@(negedge clk);start=0;
   for(yy=0;yy<H;yy=yy+1)for(xx=0;xx<W;xx=xx+1)begin
    source_valid=1;source_x=xx;source_y=yy;source_pixel=image[yy*W+xx];
    @(negedge clk);source_valid=0;repeat((xx+3*yy)%4)@(negedge clk);
   end
   source_done=1;@(negedge clk);source_done=0;
   timeout=0;while(!finished&&timeout<1000)begin @(negedge clk);timeout=timeout+1;end
   if(!finished)$fatal(1,"drain timeout");
   repeat(8)@(negedge clk);
  end
  $display("PASS tb_video_path Gaussian RAW/EDGE modes; gaps, full counts, EOF drain");$finish;
 end
endmodule
