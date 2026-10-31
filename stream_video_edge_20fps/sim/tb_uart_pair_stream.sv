`timescale 1ns/1ps
module tb_uart_pair_stream #(parameter W=32,H=24);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,v=0,sd=0;reg[7:0]p=0,q=0;reg[9:0]x=0;reg[8:0]y=0;
 wire tx;wire[31:0]dropped,packets;
 uart_pair_stream #(.W(W),.H(H)) dut(.clk(clk),.rst(rst),.start(start),.source_valid(v),.pixel(p),.other(q),.x(x),.y(y),.source_done(sd),.uart_txd(tx),.dropped(dropped),.packets(packets));
 integer f,xx,yy,fd,bits=0;reg[7:0]rx;reg[1023:0]folder;
 initial begin
  if(!$value$plusargs("VECTORS=%s",folder))$fatal(1,"vectors");
  fd=$fopen({folder,"/uart.hex"},"w");
 end
 always @(negedge tx)if(!rst)begin
  #41.666667;if(tx!==0)$fatal(1,"start bit");
  for(integer k=0;k<8;k=k+1)begin #83.333333;rx[k]=tx;end
  #83.333333;if(tx!==1)$fatal(1,"stop bit");
  $fwrite(fd,"%02x\n",rx);bits=bits+1;
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;
  for(f=1;f<=2;f=f+1)begin
   start=1;@(negedge clk);start=0;
   for(yy=0;yy<H;yy=yy+1)for(xx=0;xx<W;xx=xx+1)begin
    x=xx;y=yy;p=(xx+3*yy+f);q=~p;v=1;
    @(negedge clk);v=0;repeat(11)@(negedge clk);
   end
   sd=1;@(negedge clk);sd=0;repeat(12)@(negedge clk);
  end
  repeat(40000)@(negedge clk);
  if(dropped||packets!=2||bits!=2*(36+2*(W/4)*(H/4)))$fatal(1,"packet count %d drops=%d bytes=%d",packets,dropped,bits);
  $fclose(fd);$display("PASS tb_uart_pair_stream actual12Mbaud bytes");$finish;
 end
endmodule
