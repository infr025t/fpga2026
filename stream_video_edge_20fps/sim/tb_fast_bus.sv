`timescale 1ns/1ps
module tb_fast_bus;
 reg clk=0;always #5 clk=~clk;reg rst=1;
 integer accepted=0,bytes_seen=0,completed=0;time last_accept=0,last_fall=0,last_rise=0,changed=0;
 wire ready;wire[7:0]data;wire cs,rs,wr,rd,done;
 nt35510_bus8 #(.SETUP_CYCLES(2),.LOW_CYCLES(2),.HOLD_CYCLES(2),.GAP_CYCLES(0)) dut(
 .clk(clk),.rst(rst),.in_valid(accepted<128),.in_word(16'(accepted)),.in_rs(1'b1),.in_ready(ready),
 .lcd_data(data),.lcd_cs_n(cs),.lcd_rs(rs),.lcd_wr_n(wr),.lcd_rd_n(rd),.word_done(done));
 always @(posedge clk)if(!rst)begin
  if(accepted<128&&ready)begin
   if(last_accept && $time-last_accept!=120)$fatal(1,"cannot sustain16.667MB/s word interval=%0t",$time-last_accept);
   last_accept=$time;accepted<=accepted+1;
  end
  if(done)completed=completed+1;
 end
 always @(data)changed=$time;
 always @(negedge wr)if(!rst)begin
  if(last_rise && $time-last_rise<40)$fatal(1,"WR high too short");
  last_fall=$time;
 end
 always @(posedge wr)if(!rst&&!cs)begin
  if($time-last_fall<20 || $time-changed<40)$fatal(1,"write timing too short");
  if(data!==(bytes_seen%2?8'(bytes_seen/2):8'd0))$fatal(1,"byte mismatch %0d got%h",bytes_seen,data);
  bytes_seen=bytes_seen+1;last_rise=$time;
 end
 initial begin repeat(5)@(negedge clk);rst=0;wait(completed==128);@(negedge clk);
 if(bytes_seen!=256)$fatal(1,"lost bytes");$display("PASS tb_fast_bus words128 interval120ns timing20/40/20ns");$finish;end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
