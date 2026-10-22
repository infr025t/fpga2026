`timescale 1ns/1ps
module tb_fifo_capture;
  reg clk=0; always #5 clk=~clk;
  reg rst=1,start=0,vsync=1;
  wire rclk,rrst_n,wen,valid,sof,done,busy,error;
  reg [7:0] data=0;
  wire [7:0] pixel;
  integer ptr=0,got=0,frames=0,sofs=0,completions=0,rclk_edges=0;
  fifo_capture #(.W(4),.H(3),.READ_PERIOD(50),.FLUSH_CYCLES(100),.TIMEOUT_CYCLES(1000))
    dut(clk,rst,start,vsync,data,rclk,rrst_n,wen,sof,valid,pixel,done,busy,error);
  // Behavioral AL422 model: reset is synchronous to read clock;
  // first enabled rising edge after reset presents byte zero.
  always @(posedge rclk) begin
    rclk_edges=rclk_edges+1;
    if(!rrst_n) begin ptr=0; data<=0; end
    else begin data <= (ptr%2) ? (ptr/2+frames*20) : 8'hee; ptr=ptr+1; end
  end
  always @(posedge clk) if(!rst) begin
    if(sof)sofs=sofs+1;
    if(done)completions=completions+1;
    if(valid) begin
      if(pixel !== (got+frames*20)) $fatal(1,"byte/position error got %0d value %0d",got,pixel);
      got=got+1;
    end
  end
  task launch;
    begin
      @(negedge clk);start=1;@(negedge clk);start=0;
      if(!busy || error)$fatal(1,"new capture must accept start and clear previous timeout");
    end
  endtask
  task supply_frame;
    begin
      repeat(10) @(negedge clk);vsync=0;
      repeat(10) @(negedge clk);vsync=1;
      repeat(10) @(negedge clk);
      if(!wen) $fatal(1,"capture not armed");
      repeat(100) @(negedge clk);vsync=0;
    end
  endtask
  task capture;
    integer before_sofs,before_completions;
    begin
      before_sofs=sofs;before_completions=completions;
      launch();supply_frame();
      wait(done); repeat(2) @(negedge clk);
      if(got!=12 || error || wen || busy || !rrst_n ||
          sofs!=before_sofs+1 || completions!=before_completions+1)
        $fatal(1,"frame not complete after recovery");
      vsync=1; got=0; frames=frames+1;
      repeat(20) @(negedge clk);
    end
  endtask
  task timeout_in_phase(input integer stuck_phase);
    integer before_sofs,before_completions,before_edges;
    begin
      before_sofs=sofs;before_completions=completions;
      vsync=1;launch();
      if(stuck_phase>=2)begin
        repeat(10)@(negedge clk);vsync=0;
        repeat(10)@(negedge clk);
      end
      if(stuck_phase==3)begin
        vsync=1;repeat(10)@(negedge clk);
        if(!wen)$fatal(1,"CAPTURE timeout case never enabled writes");
      end
      if(dut.state!=stuck_phase)$fatal(1,"wrong timeout phase %0d",dut.state);
      wait(error);@(negedge clk);
      if(wen || busy || !rrst_n || sof || valid || done || got!=0)
        $fatal(1,"phase %0d timeout must release capture without output",stuck_phase);
      before_edges=rclk_edges;
      repeat(150)@(negedge clk);
      if(!error || wen || busy || !rrst_n || sofs!=before_sofs ||
          completions!=before_completions || got!=0 || rclk_edges-before_edges<2)
        $fatal(1,"phase %0d timeout must remain idle with free-running RCLK",stuck_phase);
      vsync=1;repeat(10)@(negedge clk);
      capture();
      $display("PASS fifo_capture phase %0d timeout, pin release and next-frame recovery",stuck_phase);
    end
  endtask
  integer before_reset_completions;
  initial begin
    repeat(5) @(negedge clk); rst=0;
    capture(); capture();
    timeout_in_phase(1); // VSYNC stuck high before blanking.
    timeout_in_phase(2); // VSYNC stuck low before active frame.
    timeout_in_phase(3); // VSYNC remains high while writes are enabled.
    before_reset_completions=completions;
    launch();supply_frame();wait(got==5);
    @(negedge clk);rst=1;
    repeat(3)@(negedge clk);
    if(busy || wen || !rrst_n || rclk || sof || valid || done || error ||
        completions!=before_reset_completions)
      $fatal(1,"reset during FIFO read must discard partial frame and release pins");
    got=0;vsync=1;rst=0;
    repeat(10)@(negedge clk);capture();
    if(frames!=6 || completions!=6 || sofs!=7)
      $fatal(1,"unexpected completed/partial frame totals %0d/%0d/%0d",frames,completions,sofs);
    $display("PASS fifo_capture six complete frames, three timeout phases and mid-read reset recovery");
    $finish;
  end
  initial begin #1000000; $fatal(1,"test timeout");end
endmodule
