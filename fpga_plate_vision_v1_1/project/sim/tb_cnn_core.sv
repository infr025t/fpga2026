`timescale 1ns/1ps
module tb_cnn_core;
  parameter integer NUM_CASES=12;
  parameter integer SMOKE_ONLY=0;
  reg clk=0; always #5 clk=~clk;
  reg rst=1,start=0,in_we=0;
  reg [9:0] in_addr=0;
  reg [7:0] in_data=0;
  wire busy,done,score_valid;
  wire [5:0] score_index;
  wire signed [31:0] score_data;
  wire [31:0] cycles;
  reg [7:0] inputs [0:NUM_CASES*768-1];
  reg [31:0] expected [0:NUM_CASES*36-1];
  integer case_id, i, n, elapsed, jobs=0;
  cnn_core dut(.*);

  task reset_core;
    begin
      @(negedge clk); rst=1; start=0; in_we=0;
      repeat(3) @(negedge clk);
      if (busy!==0 || done!==0 || score_valid!==0) $fatal(1,"reset did not abort outputs");
      rst=0;
    end
  endtask
  task launch;
    begin
      @(negedge clk); start=1;
      @(negedge clk); start=0;
      if (busy!==1) $fatal(1,"start must assert busy");
    end
  endtask
  task load_case(input integer c);
    begin
      if (busy!==0) $fatal(1,"input load while busy");
      for(integer k=0;k<768;k=k+1) begin
        @(negedge clk); in_we=1; in_addr=k; in_data=inputs[c*768+k];
      end
      @(negedge clk); in_we=0;
    end
  endtask
  task check_case(input integer c);
    begin
      load_case(c); launch(); n=0; elapsed=0;
      // Busy input writes/start pulses must not corrupt an active job.
      while (done!==1 && elapsed<2000000) begin
        @(negedge clk); elapsed=elapsed+1;
        in_we=(elapsed>=20 && elapsed<30); in_addr=0; in_data=8'h5a;
        start=(elapsed==40);
        if (score_valid) begin
          if (n>=36 || score_index!==n[5:0]) $fatal(1,"score count/order case=%0d n=%0d index=%0d",c,n,score_index);
          if (score_data!==expected[c*36+n])
            $fatal(1,"score mismatch case=%0d class=%0d got=%0d expected=%0d",c,n,score_data,$signed(expected[c*36+n]));
          n=n+1;
        end
        if (!busy && !done) $fatal(1,"busy dropped before done");
      end
      in_we=0; start=0;
      if (done!==1 || n!=36) $fatal(1,"incomplete case=%0d elapsed=%0d scores=%0d",c,elapsed,n);
      if (cycles==0 || cycles>2000000) $fatal(1,"invalid cycles=%0d",cycles);
      if (cycles!==elapsed) $fatal(1,"cycle report mismatch measured=%0d reported=%0d",elapsed,cycles);
      $display("PASS case=%0d scores=%0d cycles=%0d",c,n,cycles); jobs=jobs+1;
      @(negedge clk);
      if (done || score_valid || busy) $fatal(1,"completion outputs must pulse and return idle");
    end
  endtask
  initial begin
    reset_core();
    if (SMOKE_ONLY) begin
      launch(); repeat(31) @(negedge clk); reset_core();
      $display("PASS smoke reset/start/abort"); $finish;
    end
    $readmemh("vectors_input.hex",inputs);
    $readmemh("vectors_scores.hex",expected);
    // Golden data catches sign, tensor order, padding, pooling and rounding bugs.
    for(case_id=0;case_id<NUM_CASES;case_id=case_id+1) check_case(case_id);
    load_case(0); launch(); repeat(31) @(negedge clk); reset_core();
    // Abort late enough to have overwritten intermediate RAM; reload and reuse.
    load_case(0); launch();
    repeat(250000) @(negedge clk);
    reset_core(); check_case(NUM_CASES-1);
    $display("PASS cnn_core all %0d complete jobs plus two reset aborts",jobs);
    $finish;
  end
  initial begin #3000000000ns; $fatal(1,"global timeout"); end
endmodule
