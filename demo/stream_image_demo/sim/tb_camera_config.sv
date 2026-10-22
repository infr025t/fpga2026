`timescale 1ns/1ps
module tb_camera_config;
  reg clk=0;always #5 clk=~clk;
  reg rst=1;
  tri1 scl,sda;
  wire done,error;
  // SCCB write sink: ACK the ninth bit, decode all three-byte transactions.
  reg ack=0,ack_enable=1;assign sda=(ack && ack_enable)?1'b0:1'bz;
  reg active=0;
  integer bits=0, bytes=0,transactions=0,bus_edges=0;
  reg[7:0] shift=0;
  camera_config #(.QUARTER_CYCLES(2),.POWER_WAIT(10),.REG_WAIT(8)) dut(clk,rst,scl,sda,done,error);
  always @(scl or sda)bus_edges=bus_edges+1;
  always @(negedge sda) if(scl===1'b1) begin active=1;bits=0;bytes=0;end
  always @(posedge sda) if(scl===1'b1 && active) begin
    if(bytes!=3) $fatal(1,"bad transaction bytes=%0d",bytes);
    transactions=transactions+1;active=0;
  end
  always @(posedge scl) if(active) begin
    if(bits<8) begin
      shift={shift[6:0],sda};bits=bits+1;
      if(bits==8)begin
        if(bytes==0 && shift!=8'h42)$fatal(1,"wrong SCCB address");
        if(transactions==0 && bytes==1 && shift!=8'h12)$fatal(1,"reset register");
        if(transactions==0 && bytes==2 && shift!=8'h80)$fatal(1,"reset value");
        if(transactions==18 && bytes==2 && shift!=8'h0c)$fatal(1,"UYVY requires TSLB bit 3 = 1");
        bytes=bytes+1;
      end
    end else bits=0;
  end
  always @(negedge scl) if(active) ack=(bits==8);else ack=0;
  task reset_sink(input integer enable_ack);
    begin
      @(negedge clk);rst=1;active=0;ack=0;ack_enable=enable_ack;
      transactions=0;bits=0;bytes=0;
      repeat(5)@(negedge clk);rst=0;
    end
  endtask
  integer failed_edges;
  initial begin
    repeat(5)@(negedge clk);rst=0;
    wait(done);if(error || transactions!=39)$fatal(1,"config incomplete");
    $display("PASS camera_config %0d transactions",transactions);
    reset_sink(0);
    wait(error);#1;
    if(done || scl!==1'b1 || sda!==1'b1 || active || transactions!=1)
      $fatal(1,"NACK error must be published only after complete STOP and bus release");
    failed_edges=bus_edges;
    repeat(250)@(negedge clk);
    if(done || !error || scl!==1'b1 || sda!==1'b1 || transactions!=1 || bus_edges!=failed_edges)
      $fatal(1,"NACK must keep bus released and remain failed until reset");
    $display("PASS camera_config NACK completes STOP before error and leaves bus idle");
    reset_sink(1);
    if(error || done)$fatal(1,"reset must clear failed configuration status");
    wait(done);#1;
    if(error || transactions!=39 || scl!==1'b1 || sda!==1'b1)
      $fatal(1,"configuration must restart all 39 registers after NACK reset");
    $display("PASS camera_config reset after NACK restores complete 39-register configuration");
    $finish;
  end
  initial begin #2000000;$fatal(1,"timeout");end
endmodule
