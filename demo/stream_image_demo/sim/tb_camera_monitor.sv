`timescale 1ns/1ps
module tb_camera_monitor;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,enabled=0,vs=1,href=0,wen=0;
  wire vs_seen,href_seen,wen_seen,overlap_seen;
  wire[15:0]lines,high_lines,low_lines;
  wire href_vs_high,href_vs_low;
  camera_monitor dut(clk,rst,enabled,vs,href,wen,vs_seen,href_seen,wen_seen,overlap_seen,lines,href_vs_high,href_vs_low,high_lines,low_lines);
  task hold_cycles(input integer n);repeat(n)@(negedge clk);endtask
  task line_pulse;begin href=1;hold_cycles(8);href=0;hold_cycles(8);end endtask
  initial begin
    hold_cycles(5);rst=0;hold_cycles(5);
    // Initialization activity must not count as a successful capture.
    vs=0;line_pulse();wen=1;hold_cycles(6);wen=0;hold_cycles(5);
    if(vs_seen||href_seen||wen_seen||overlap_seen||lines)$fatal(1,"disabled monitor latched events");
    enabled=1;hold_cycles(5);vs=1;hold_cycles(5);line_pulse();
    if(!vs_seen||!href_seen||wen_seen||overlap_seen)$fatal(1,"independent sensor activity");
    if(!href_vs_high || href_vs_low)$fatal(1,"HREF high-VSYNC observation");
    vs=0;hold_cycles(5);line_pulse();
    if(!href_vs_low)$fatal(1,"HREF low-VSYNC observation");
    wen=1;hold_cycles(5);repeat(240)line_pulse();wen=0;hold_cycles(5);
    if(lines!=240 || !wen_seen || !overlap_seen)$fatal(1,"capture must count 240 lines, got %0d",lines);
    line_pulse();if(lines!=240)$fatal(1,"idle HREF corrupted last capture count");
    wen=1;hold_cycles(10);wen=0;hold_cycles(5);
    if(lines!=0)$fatal(1,"zero-line capture not reported");
    // Account for the two-flop HREF synchronizer: WEN rises on the same
    // observation cycle as the first synchronized HREF rising edge.
    href=1;hold_cycles(2);
    if(dut.href_sync[1]!==1'b1 || dut.href_prev!==1'b0 || dut.wen_prev!==1'b0)
      $fatal(1,"coincident-edge test stimulus is not aligned");
    wen=1;hold_cycles(6);
    href=0;hold_cycles(8);wen=0;hold_cycles(5);
    if(lines!=1)$fatal(1,"first line lost when WEN and HREF rise together: %0d",lines);
    // Starting during an existing HREF high level must not invent an edge.
    href=1;hold_cycles(5);wen=1;hold_cycles(5);
    href=0;hold_cycles(8);wen=0;hold_cycles(5);
    if(lines!=0)$fatal(1,"existing HREF level counted as a new line: %0d",lines);
    // Start clean phase boundaries, then test both polarity arrangements.
    vs=1;hold_cycles(5);vs=0;hold_cycles(5);vs=1;hold_cycles(5);
    repeat(240)line_pulse();vs=0;hold_cycles(5);
    if(high_lines!=240)$fatal(1,"high VSYNC phase lines %0d",high_lines);
    repeat(3)line_pulse();vs=1;hold_cycles(5);
    if(low_lines!=3)$fatal(1,"low VSYNC phase lines %0d",low_lines);
    // Reversed arrangement: no lines high, 240 lines low.
    vs=0;hold_cycles(5);if(high_lines!=0)$fatal(1,"high phase stale count");
    repeat(240)line_pulse();vs=1;hold_cycles(5);
    if(low_lines!=240)$fatal(1,"reverse phase count");
    rst=1;hold_cycles(5);
    if(vs_seen||href_seen||wen_seen||overlap_seen||lines||href_vs_high||href_vs_low||high_lines||low_lines)$fatal(1,"reset did not clear diagnostics");
    $display("PASS camera monitor sensor activity, 240-line capture, zero-line capture, coincident first line, VSYNC phase counts and reset");$finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
