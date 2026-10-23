`timescale 1ns/1ps
module tb_vision_status;
  localparam integer CPB=4,N=58;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,start=0;reg[7:0]flags=0;reg[383:0]snapshot=0;
  wire tx,busy;
  vision_status_tx #(.CLKS_PER_BIT(CPB)) dut(clk,rst,start,flags,snapshot,tx,busy);
  reg[7:0]bytes[0:N-1];reg[15:0]crc;integer fd,f,i,j,driver;
  function[15:0]update_crc(input[15:0]c,input[7:0]b);
    reg[15:0]v;integer n;
    begin v=c^{b,8'b0};for(n=0;n<8;n=n+1)v=v[15]?(v<<1)^16'h1021:v<<1;update_crc=v;end
  endfunction
  function[31:0]u32(input integer off);
    u32={bytes[off+3],bytes[off+2],bytes[off+1],bytes[off]};
  endfunction
  task get_byte(output[7:0]b);
    integer k;
    begin @(negedge tx);#(CPB*10/2);if(tx!==0)$fatal(1,"status UART start");
      for(k=0;k<8;k=k+1)begin #(CPB*10);b[k]=tx;end
      #(CPB*10);if(tx!==1)$fatal(1,"status UART stop");end
  endtask
  initial begin
    repeat(4)@(negedge clk);rst=0;
    for(driver=0;driver<2;driver=driver+1)begin
      for(j=0;j<12;j=j+1)snapshot[j*32+:32]=(driver+1)*100+j*17;
      flags=(driver==0)?9:2;start=1;@(negedge clk);start=0;
      snapshot={384{1'b1}};flags=15;
      wait(!busy);repeat(3)@(negedge clk);
    end
  end
  initial begin
    fd=$fopen("vision_status_wire.bin","wb");if(!fd)$fatal(1,"status wire export");
    for(f=0;f<2;f=f+1)begin
      for(i=0;i<N;i=i+1)begin get_byte(bytes[i]);$fwrite(fd,"%c",bytes[i]);end
      if(u32(0)!==32'h31545356 || bytes[4]!==1 || bytes[5]!==((f==0)?9:2) ||
         bytes[6]!==N || bytes[7]!==0)$fatal(1,"status header");
      for(i=0;i<12;i=i+1)if(u32(8+i*4)!==(f+1)*100+i*17)$fatal(1,"status snapshot latching");
      crc=16'hffff;for(i=4;i<N-2;i=i+1)crc=update_crc(crc,bytes[i]);
      if({bytes[N-1],bytes[N-2]}!==crc)$fatal(1,"status CRC");
    end
    $fclose(fd);wait(!busy);
    $display("PASS VST1 two status snapshots, UART, CRC and input latching");$finish;
  end
  initial begin #500000;$fatal(1,"status timeout");end
endmodule
