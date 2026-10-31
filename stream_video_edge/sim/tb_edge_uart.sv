`timescale 1ns/1ps
module tb_edge_uart;
 localparam W=32,H=24,N=(W-10)*(H-10),B=N+52;
 reg clk=0;always #5 clk=~clk;reg rst=1,start=0,valid=0,sdone=0,view=0;
 reg[7:0]pixel=0;reg[9:0]x=0;reg[8:0]y=0;reg[31:0]fid=100;
 wire ready,tx,busy,done;wire[7:0]error;
 edge_uart_stream #(W,H) dut(.clk(clk),.rst(rst),.start(start),.view_edge(view),
 .frame_id(fid),.edge_threshold(11'd128),
 .source_valid(valid),.source_pixel(pixel),.source_x(x),.source_y(y),.source_done(sdone),.source_error(1'b0),
 .source_ready(ready),.uart_txd(tx),.busy(busy),.done(done),.error(error));
 reg[7:0]image[0:W*H-1],expected[0:B-1],received_data[0:B-1],rx;
 integer count=0,b,i,m;string path,name;
 initial forever begin
  @(negedge tx);if(!rst)begin
   #125;for(b=0;b<8;b=b+1)begin rx[b]=tx;#83.333333;end
   if(tx!==1)$fatal(1,"UART stop");
   if(count>=B)$fatal(1,"extra wire byte");received_data[count]=rx;count=count+1;#41.666667;
  end
 end
 always @(posedge clk)if(!rst&&error!=0)$fatal(1,"UART core error %h",error);
 initial begin
  if(!$value$plusargs("VECTORS=%s",path))$fatal(1,"missing vectors");
  $readmemh({path,"/image.hex"},image);repeat(5)@(negedge clk);rst=0;
  for(m=0;m<2;m=m+1)begin
   view=m;fid=100+m;count=0;
   name=$sformatf("%s/wire_%0d.hex",path,m);$readmemh(name,expected);
   @(negedge clk);start=1;@(negedge clk);start=0;wait(ready);
   for(i=0;i<W*H;i=i+1)begin
    @(negedge clk);if(!ready)$fatal(1,"source tail was backpressured pixel%0d",i);
    valid=1;pixel=image[i];x=i%W;y=i/W;@(negedge clk);valid=0;repeat(98)@(negedge clk);
   end
   sdone=1;@(negedge clk);sdone=0;wait(done);@(negedge clk);
   if(count!=B)$fatal(1,"wire length %0d/%0d",count,B);
   for(i=0;i<B;i=i+1)if(received_data[i]!==expected[i])$fatal(1,"wire mode%0d index%0d got%h expected%h",m,i,received_data[i],expected[i]);
   $display("EVG2_PASS filter%0d view%0d bytes%0d",1'b1,view,count);repeat(100)@(negedge clk);
  end
  $display("PASS tb_edge_uart two_views_gaussian source_tail_crc physical_pin");$finish;
 end
 initial begin #10000000;$fatal(1,"UART watchdog");end
endmodule
