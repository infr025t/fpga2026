`timescale 1ns/1ps
module tb_camera_readback;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,enable=0,slave_low=0,nack=0;
  tri1 scl,sda;assign sda=slave_low?1'b0:1'bz;
  wire done,error;wire[31:0]values;
  camera_readback #(.QUARTER_CYCLES(4)) dut(clk,rst,enable,scl,sda,done,error,values);
  reg[7:0]value;integer round,j,k;
  function[7:0]address(input integer n);
    case(n)0:address=8'h0a;1:address=8'h15;2:address=8'h3a;3:address=8'h12;endcase
  endfunction
  function[7:0]answer(input integer n);
    case(n)0:answer=8'h76;1:answer=8'h02;2:answer=8'h0c;3:answer=8'h00;endcase
  endfunction
  task start_seen;begin
    @(negedge sda);while(scl!==1'b1)@(negedge sda);
  end endtask
  task stop_seen;begin
    @(posedge sda);while(scl!==1'b1)@(posedge sda);
  end endtask
  task receive_byte(output reg[7:0]b);integer i;begin
    for(i=7;i>=0;i=i-1)begin @(posedge scl);b[i]=sda;end
    @(negedge scl);slave_low=!nack;
    @(posedge scl);@(negedge scl);slave_low=0;
  end endtask
  task send_byte(input reg[7:0]b);integer i;begin
    // Entry is the falling edge ending address ACK.
    for(i=7;i>=0;i=i-1)begin slave_low=~b[i];@(posedge scl);@(negedge scl);end
    slave_low=0;@(posedge scl);
    if(sda!==1'b1)$fatal(1,"master must NACK final read byte");
    @(negedge scl);
  end endtask
  initial begin
    for(round=0;round<2;round=round+1)begin
      rst=1;enable=0;nack=(round==1);repeat(5)@(negedge clk);rst=0;
      repeat(10)@(negedge clk);
      if(scl!==1 || sda!==1 || done)$fatal(1,"idle bus ownership");
      enable=1;
      for(j=0;j<4;j=j+1)begin
        start_seen();receive_byte(value);if(value!=8'h42)$fatal(1,"write address");
        receive_byte(value);if(value!=address(j))$fatal(1,"register pointer");
        stop_seen();start_seen();receive_byte(value);if(value!=8'h43)$fatal(1,"read address");
        send_byte(answer(j));stop_seen();
      end
      wait(done);repeat(5)@(negedge clk);
      if(values!==32'h000c0276 || error!==nack)$fatal(1,"readback values/status %h %b",values,error);
      if(scl!==1 || sda!==1)$fatal(1,"bus not released after done");
    end
    $display("PASS SCCB four-register readback, STOP-separated addressing, final NACK and error status");$finish;
  end
  initial begin #1000000;$fatal(1,"readback timeout");end
endmodule
