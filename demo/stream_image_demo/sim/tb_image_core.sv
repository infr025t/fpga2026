`timescale 1ns/1ps
module tb_image_core;
  parameter W=320,H=240;
  reg clk=0; always #5 clk=~clk;
  reg rst=1,frame_start=0,edge_mode=0,in_valid=0;
  reg [10:0] threshold=0;
  reg [7:0] in_pixel=0;
  wire out_valid,done;
  wire [7:0] out_pixel;
  wire [16:0] out_addr;
  wire [31:0] bright_count,sum_x,sum_y;
  image_core #(.W(W),.H(H)) dut(.*);
  integer src[0:W*H-1],expected[0:(W-2)*(H-2)-1];
  integer count_expected,sx_expected,sy_expected,received,done_seen;
  integer gx,gy,mag,x,y,k,f,seed=1234567,r;
  integer mode,thresh;
  always @(posedge clk) begin
    #1;
    if (!rst && !frame_start) begin
      if(out_valid) begin
        if(received >= (W-2)*(H-2)) $fatal(1,"extra output");
        if(out_addr !== received || out_pixel !== expected[received])
          $fatal(1,"pixel mismatch frame=%0d addr=%0d expected_addr=%0d value=%0d expected=%0d",f,out_addr,received,out_pixel,expected[received]);
        received=received+1;
      end
      if(done) begin
        if(out_valid) $fatal(1,"done must follow final output");
        if(received != (W-2)*(H-2)) $fatal(1,"early done");
        if(bright_count !== count_expected || sum_x !== sx_expected || sum_y !== sy_expected)
          $fatal(1,"statistics mismatch count=%0d/%0d sx=%0d/%0d sy=%0d/%0d",bright_count,count_expected,sum_x,sx_expected,sum_y,sy_expected);
        done_seen=done_seen+1;
      end
    end
  end
  initial begin
    received=0; done_seen=0;
    repeat(4) @(negedge clk); rst=0;
    for(f=0;f<12;f=f+1) begin
      mode=f%2; thresh=(f==1)?0:((f==3)?2047:((f==5)?1020:180));
      for(y=0;y<H;y=y+1) for(x=0;x<W;x=x+1) begin
        case(f/2)
          0: src[y*W+x]=0;
          1: src[y*W+x]=255;
          2: src[y*W+x]=(x>W/2)?255:0;
          3: src[y*W+x]=(x*17+y*11)%256;
          4: src[y*W+x]=(x>=3&&x<W-3&&y>=2&&y<H-2)?255:0;
          default: begin r=$random(seed); src[y*W+x]=r&255; end
        endcase
      end
      count_expected=0; sx_expected=0; sy_expected=0;k=0;
      for(y=1;y<H-1;y=y+1) for(x=1;x<W-1;x=x+1) begin
        gx=src[(y-1)*W+x+1]+2*src[y*W+x+1]+src[(y+1)*W+x+1]
          -src[(y-1)*W+x-1]-2*src[y*W+x-1]-src[(y+1)*W+x-1];
        gy=src[(y+1)*W+x-1]+2*src[(y+1)*W+x]+src[(y+1)*W+x+1]
          -src[(y-1)*W+x-1]-2*src[(y-1)*W+x]-src[(y-1)*W+x+1];
        mag=((gx<0)?-gx:gx)+((gy<0)?-gy:gy);
        expected[k]=mode?((mag>=thresh)?255:0):src[y*W+x]; k=k+1;
        if(src[y*W+x]>=128) begin count_expected=count_expected+1; sx_expected=sx_expected+x; sy_expected=sy_expected+y; end
      end
      @(negedge clk); frame_start=1;edge_mode=mode;threshold=thresh;
      @(negedge clk); frame_start=0; received=0; done_seen=0;
      edge_mode=!mode;threshold=777; // inputs must be latched at frame_start
      for(k=0;k<W*H;k=k+1) begin
        in_valid=1;in_pixel=src[k];
        @(negedge clk);in_valid=0;
        repeat(3+(k%5)) @(negedge clk);
      end
      repeat(10) @(negedge clk);
      if(done_seen!=1 || received!=(W-2)*(H-2)) $fatal(1,"missing frame completion outputs=%0d done=%0d",received,done_seen);
      $display("PASS frame=%0d mode=%0d threshold=%0d pixels=%0d bright=%0d",f,mode,thresh,received,bright_count);
    end
    $display("PASS_IMAGE_CORE W=%0d H=%0d frames=12",W,H); $finish;
  end
  initial begin #100000000; $fatal(1,"timeout"); end
endmodule
