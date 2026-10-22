`timescale 1ns/1ps
module tb_transport;
  localparam W=4,H=2,CPB=4,N=32+W*H+2;
  reg clk=0,rst=1,start=0,mode=1;
  always #5 clk=~clk;
  reg [10:0] threshold=180;
  reg [31:0] frame_id=7,bc=2,sx=7,sy=5;
  wire [16:0] addr;
  reg [7:0] rd;
  wire busy,done,tx;
  reg [7:0] mem[0:W*H-1],received[0:N-1];
  integer fd,i,f;
  reg [15:0] crc;
  frame_sender #(.W(W),.H(H),.CLKS_PER_BIT(CPB)) dut
    (.clk(clk),.rst(rst),.start(start),.edge_mode(mode),.threshold(threshold),
     .frame_id(frame_id),.bright_count(bc),.sum_x(sx),.sum_y(sy),
     .ram_addr(addr),.ram_data(rd),.busy(busy),.done(done),.uart_txd(tx));
  always @(posedge clk) rd<=mem[addr];
  function [15:0] update_crc(input [15:0] c,input [7:0] b);
    reg [15:0] v; integer k;
    begin v=c^{b,8'b0}; for(k=0;k<8;k=k+1) v=v[15]?(v<<1)^16'h1021:v<<1; update_crc=v; end
  endfunction
  task get_byte(output [7:0] b);
    integer k;
    begin
      @(negedge tx); #(CPB*10/2);
      if(tx!==0) $fatal(1,"bad start bit");
      for(k=0;k<8;k=k+1) begin #(CPB*10); b[k]=tx; end
      #(CPB*10); if(tx!==1) $fatal(1,"bad stop bit");
    end
  endtask
  initial begin
    fd=$fopen("wire.bin","wb");
    for(i=0;i<W*H;i=i+1) mem[i]=i*31+5;
    repeat(5) @(negedge clk); rst=0;
    for(f=0;f<2;f=f+1) begin
      frame_id=7+f; mode=(f==0); threshold=180+f;
      @(negedge clk); start=1;
      @(negedge clk); start=0;
      // Mutate live metadata: transmitted values must remain latched.
      frame_id=999; threshold=999; mode=~mode;
      for(i=0;i<N;i=i+1) begin get_byte(received[i]); $fwrite(fd,"%c",received[i]); end
      if({received[3],received[2],received[1],received[0]}!==32'h31475046) $fatal(1,"magic");
      if(received[4]!=1 || received[5]!=(f==0) || received[6]!=W || received[8]!=H) $fatal(1,"header dimensions/mode");
      if(received[10]!=180+f || received[12]!=7+f || received[16]!=W*H) $fatal(1,"latched header");
      if(received[20]!=2 || received[24]!=7 || received[28]!=5) $fatal(1,"statistics");
      for(i=0;i<W*H;i=i+1) if(received[32+i]!==mem[i]) $fatal(1,"pixel %0d got %0d",i,received[32+i]);
      crc=16'hffff;
      for(i=4;i<N-2;i=i+1) crc=update_crc(crc,received[i]);
      if({received[N-1],received[N-2]}!==crc) $fatal(1,"crc");
      wait(done); @(negedge clk);
      if(busy) $fatal(1,"busy after done");
    end
    $fclose(fd); $display("PASS transport two frames UART/header/payload/CRC/latching"); $finish;
  end
  initial begin #1000000; $fatal(1,"timeout"); end
endmodule
