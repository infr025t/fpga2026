`timescale 1ns/1ps
module tb_stream_buffers;
  wire d1,d3,dq;
  fifo_case #(.DEPTH(1)) one_entry(d1);
  fifo_case #(.DEPTH(3)) odd_depth(d3);
  frame_queue_case queue_case(dq);
  initial begin wait(d1 && d3 && dq);
    $display("PASS bounded FIFO depth 1/3; full replacement/overflow; display whole-frame drop, stalls, abort, malformed frame, reset and order");$finish;end
  initial begin #1000000;$fatal(1,"stream buffer timeout");end
endmodule
module fifo_case #(parameter integer DEPTH=3)(output reg finished=0);
  reg clk=0;always #5 clk=~clk;
  reg rst=1,valid=0,ready=0;reg[15:0]data=0;
  wire ir,ov,overflow;wire[15:0]od;wire[$clog2(DEPTH+1)-1:0]level;
  pixel_fifo #(.WIDTH(16),.DEPTH(DEPTH)) dut(clk,rst,valid,data,ir,ov,od,ready,overflow,level);
  integer expected[0:255],wp=0,rp=0,i;
  always @(posedge clk)if(!rst)begin
    if(ov && ready)begin if(od!==expected[rp])$fatal(1,"ingress FIFO order");rp=rp+1;end
    if(valid && ir)begin expected[wp]=data;wp=wp+1;end
    if(level>DEPTH)$fatal(1,"unbounded ingress FIFO");
  end
  initial begin
    repeat(3)@(negedge clk);rst=0;
    for(i=0;i<DEPTH;i=i+1)begin valid=1;data=i;@(negedge clk);end
    data=999;@(negedge clk);
    if(!overflow || ir || level!=DEPTH)$fatal(1,"FIFO overflow not reported");
    ready=1;data=100;@(negedge clk);valid=0;
    repeat(DEPTH+3)@(negedge clk);
    if(ov || wp!=DEPTH+1 || rp!=wp)$fatal(1,"FIFO drain/replacement");
    rst=1;@(negedge clk);if(ov || level!=0)$fatal(1,"FIFO reset");finished=1;
  end
endmodule
module frame_queue_case(output reg finished=0);
  reg clk=0;always #5 clk=~clk;
  reg rst=1,start=0,abort_frame=0,iv=0,last=0,processed=0,ready=0;
  reg[31:0]id=0;reg[7:0]pixel=0;
  wire dropped,bad,ov,sof,eol,eof,delivered,view;wire[1:0]level;wire[7:0]od;wire[31:0]oid;
  display_frame_queue #(.W(3),.H(2)) dut(clk,rst,start,abort_frame,id,processed,
    iv,pixel,last,dropped,bad,level,ov,ready,od,oid,view,sof,eol,eof,delivered);
  integer expected_ids[0:4],packets=0,index=0,drops=0,errors=0,cycle=0;
  reg hold=0;reg[44:0]held;
  always @(posedge clk)begin
    cycle=cycle+1;
    if(rst)hold=0;
    else begin
      if(hold && {oid,view,sof,eol,eof,od}!==held)$fatal(1,"stalled display changed payload");
      hold=ov && !ready;held={oid,view,sof,eol,eof,od};
      if(level>2)$fatal(1,"unbounded display frame queue");
      if(dropped)drops=drops+1;if(bad)errors=errors+1;
      if(ov && ready)begin
        if(packets>=5 || oid!==expected_ids[packets] || od!==((oid*20+index)&255) ||
           view!==(oid%2) || sof!==(index==0) || eol!==(index%3==2) || eof!==(index==5))
          $fatal(1,"display packet/order/raster mismatch id=%0d index=%0d pixel=%0d",oid,index,od);
        if(eof)begin packets=packets+1;index=0;end else index=index+1;
      end
    end
  end
  task begin_frame(input integer frame);
    begin @(negedge clk);id=frame;processed=frame%2;start=1;@(negedge clk);start=0;end
  endtask
  task send_pixels(input integer count,ending);
    integer j;
    begin
      for(j=0;j<count;j=j+1)begin iv=1;pixel=(id*20+j)&255;last=ending && j==count-1;@(negedge clk);end
      iv=0;last=0;
    end
  endtask
  task send_frame(input integer frame);
    begin begin_frame(frame);send_pixels(6,1);end
  endtask
  // Deterministic backpressure during consumption, including final pixels.
  reg run_reader=0;
  always @(negedge clk)if(run_reader)ready=(cycle%4!=1);
  initial begin
    expected_ids[0]=1;expected_ids[1]=2;expected_ids[2]=4;expected_ids[3]=6;expected_ids[4]=10;
    repeat(3)@(negedge clk);rst=0;
    begin_frame(1);send_pixels(3,0);repeat(4)@(negedge clk);
    if(ov)$fatal(1,"uncommitted frame became visible");
    // Continue this partial fixture without restarting its input index.
    iv=1;pixel=23;@(negedge clk);pixel=24;@(negedge clk);pixel=25;last=1;@(negedge clk);iv=0;last=0;
    send_frame(2);send_frame(3);repeat(3)@(negedge clk);
    if(drops!=1 || level!=2)$fatal(1,"slow-display whole frame drop");
    run_reader=1;
    wait(packets==1);send_frame(4);
    wait(packets==3);@(negedge clk);run_reader=0;ready=0;
    begin_frame(5);send_pixels(3,0);abort_frame=1;@(negedge clk);abort_frame=0;
    send_frame(6);run_reader=1;wait(packets==4);@(negedge clk);run_reader=0;ready=0;
    begin_frame(7);send_pixels(2,1);begin_frame(8);send_pixels(6,0);
    repeat(3)@(negedge clk);if(errors!=2 || ov)$fatal(1,"malformed frame leaked");
    send_frame(9);wait(ov);@(negedge clk);rst=1;repeat(2)@(negedge clk);rst=0;
    if(ov || level!=0)$fatal(1,"queue reset kept old frame");
    send_frame(10);run_reader=1;wait(packets==5);repeat(3)@(negedge clk);
    if(level!=0 || ov)$fatal(1,"display queue did not drain");finished=1;
  end
endmodule
