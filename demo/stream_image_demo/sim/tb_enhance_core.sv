`timescale 1ns/1ps
module tb_enhance_core;
  wire small_done,qvga_done;
  enhance_case small_case(small_done);
  enhance_case #(.W(320),.H(240),.FRAMES(3),.FILE_NAME("enhance_qvga.txt")) qvga(qvga_done);
  initial begin wait(small_done && qvga_done);
    $display("PASS enhancement continuous/bubbled pixels, controls latched, aborted startup, small/QVGA raster exports");$finish;end
  initial begin #20000000;$fatal(1,"enhancement timeout");end
endmodule
module enhance_case #(parameter integer W=9,H=8,FRAMES=5,
  parameter FILE_NAME="enhance_small.txt")(output reg finished=0);
  reg clk=0;always #5 clk=~clk;
  reg rst=1,start=0,valid=0;reg[7:0]pixel=0,gf=16,gc=16,lim=255;
  wire ov,sof,eol,eof;wire[7:0]raw,fine,coarse,enhanced;wire[15:0]x,y;
  enhance_core #(.W(W),.H(H)) dut(clk,rst,start,valid,pixel,gf,gc,lim,
    ov,raw,fine,coarse,enhanced,x,y,sof,eol,eof);
  integer frame=-1,xx,yy,i,fd,outputs=0,row_run=0,full_runs=0;
  function[7:0]source_y(input integer f,px,py);
    begin
      if(f==0)source_y=80;
      else if(f==1)source_y=((px+py)%2)?255:0;
      else if(f==3)source_y=((px<W/2)?40:220)+(px+py)%3;
      else source_y=(px*17+py*31+f*43)%256;
    end
  endfunction
  always @(posedge clk)if(ov)begin
    if(frame<0)$fatal(1,"aborted input leaked enhancement output");
    $fdisplay(fd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",frame,x,y,raw,fine,coarse,enhanced,sof,eol,eof);
    outputs=outputs+1;row_run=row_run+1;
    if(eol)begin
      if(row_run==W-4)full_runs=full_runs+1;
      row_run=0;
    end
  end else row_run=0;
  initial begin
    fd=$fopen(FILE_NAME,"w");if(!fd)$fatal(1,"enhancement export");
    $fdisplay(fd,"%0d %0d %0d",W,H,FRAMES);
    repeat(3)@(negedge clk);rst=0;
    // Abandon three rows before a complete 5x5 footprint exists.
    start=1;valid=1;pixel=99;@(negedge clk);start=0;
    for(i=1;i<W*3;i=i+1)@(negedge clk);
    valid=0;repeat(12)@(negedge clk);
    for(frame=0;frame<FRAMES;frame=frame+1)begin
      case(frame)
        0:begin gf=16;gc=16;lim=255;end
        1:begin gf=48;gc=32;lim=255;end
        2:begin gf=24;gc=20;lim=32;end
        3:begin gf=0;gc=0;lim=0;end
        4:begin gf=255;gc=255;lim=255;end
      endcase
      start=1;valid=1;pixel=source_y(frame,0,0);@(negedge clk);start=0;
      for(i=1;i<W*H;i=i+1)begin
        if(frame==2 && i%7==0)begin valid=0;repeat(3)@(negedge clk);end
        valid=1;pixel=source_y(frame,i%W,i/W);
        // Deliberately change controls after the frame-start acceptance.
        gf=0;gc=0;lim=0;
        @(negedge clk);
      end
      valid=0;@(posedge clk);while(!eof)@(posedge clk);@(negedge clk);repeat(3)@(negedge clk);
    end
    if(outputs!=FRAMES*(W-4)*(H-4))$fatal(1,"enhancement output count got=%0d expected=%0d",outputs,FRAMES*(W-4)*(H-4));
    if(full_runs==0)$fatal(1,"enhancement never sustained one pixel/clock");
    $fclose(fd);finished=1;
  end
endmodule
