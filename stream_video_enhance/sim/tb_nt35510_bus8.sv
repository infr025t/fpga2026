`timescale 1ns/1ps
module nt35510_bus8_case #(
  parameter integer SETUP_CYCLES=2,LOW_CYCLES=3,HOLD_CYCLES=2,GAP_CYCLES=1
)(output reg finished=0);
  reg clk=0;always #5 clk=~clk;
  reg rst=1,in_valid=0,in_rs=0;reg [15:0] in_word=0;
  wire ready,cs_n,rs,wr_n,rd_n,done;wire [7:0] data;
  nt35510_bus8 #(SETUP_CYCLES,LOW_CYCLES,HOLD_CYCLES,GAP_CYCLES) dut(
    .clk(clk),.rst(rst),.in_valid(in_valid),.in_word(in_word),.in_rs(in_rs),.in_ready(ready),
    .lcd_data(data),.lcd_cs_n(cs_n),.lcd_rs(rs),.lcd_wr_n(wr_n),.lcd_rd_n(rd_n),.word_done(done));
  reg [7:0] expected_data[0:2047];reg expected_rs[0:2047];
  integer write_index=0,read_index=0,bytes_in_cs=0;
  integer accepted=0,completed=0,cancelled=0,bytes_seen=0;
  time data_changed=0,rs_changed=0,cs_fell=0,wr_fell=0,wr_rose=0,byte_rose=0,accepted_at=0;
  reg have_fall=0,have_rise=0,have_byte=0;
  reg [31:0] random_state=32'h21854a73;
  integer i,j;
  always @(posedge clk)if(!rst && in_valid && ready)begin
    expected_data[write_index]=in_word[15:8];expected_rs[write_index]=in_rs;
    expected_data[write_index+1]=in_word[7:0];expected_rs[write_index+1]=in_rs;
    write_index=write_index+2;accepted=accepted+1;accepted_at=$time;
  end
  always @(posedge rst)begin
    if(accepted>completed+cancelled)cancelled=cancelled+1;
    read_index=write_index;bytes_in_cs=0;have_fall=0;have_rise=0;have_byte=0;
  end
  always @(data)begin
    if(!rst && have_rise && $time-wr_rose<10)$fatal(1,"bus data hold below 10ns");
    data_changed=$time;
  end
  always @(rs)begin
    if(!rst)begin
      if(!cs_n && $time!=accepted_at)$fatal(1,"RS changed inside a selected word");
      if(have_rise && $time-wr_rose<2)$fatal(1,"RS hold below 2ns");
    end
    rs_changed=$time;
  end
  always @(negedge cs_n)if(!rst)begin
    if(wr_n!==1 || rd_n!==1)$fatal(1,"word selection while a bus strobe is active");
    if(read_index>=write_index)$fatal(1,"CS without accepted input word");
    cs_fell=$time;bytes_in_cs=0;
  end
  always @(negedge wr_n)if(!rst)begin
    if(cs_n!==0 || rd_n!==1)$fatal(1,"write strobe without selection or with read active");
    if($time-data_changed<15)$fatal(1,"data setup below 15ns");
    if(have_rise && $time-wr_rose<15)$fatal(1,"WR high below 15ns");
    wr_fell=$time;have_fall=1;
  end
  // Independent panel-side scoreboard: only physical WR rising edges count.
  always @(posedge wr_n)if(!rst && !cs_n)begin
    if(!have_fall || $time-wr_fell<15)$fatal(1,"WR low below 15ns");
    if(have_byte && $time-byte_rose<33)$fatal(1,"write cycle below 33ns");
    if(read_index>=write_index || data!==expected_data[read_index] || rs!==expected_rs[read_index])
      $fatal(1,"physical byte mismatch at %0d got=%h rs=%b",read_index,data,rs);
    read_index=read_index+1;bytes_in_cs=bytes_in_cs+1;bytes_seen=bytes_seen+1;
    if(bytes_in_cs>2)$fatal(1,"more than two bytes in one CS word");
    wr_rose=$time;byte_rose=$time;have_rise=1;have_byte=1;have_fall=0;
  end
  always @(posedge cs_n)if(!rst && have_byte)begin
    if(wr_n!==1 || bytes_in_cs!=2)$fatal(1,"CS released before two byte writes");
    if($time-wr_rose<10)$fatal(1,"CS release before last-byte hold");
  end
  always @(posedge done)begin
    if(rst || cs_n!==1 || wr_n!==1 || rd_n!==1 || bytes_in_cs!=2 || read_index!=write_index)
      $fatal(1,"word_done before the physical transfer finishes");
    completed=completed+1;
  end
  always @(negedge clk)if(rd_n!==1)$fatal(1,"read output must remain inactive");
  task send_word(input [15:0] value,input bit command_data);
    begin
      @(negedge clk);in_word=value;in_rs=command_data;in_valid=1;
      @(posedge clk);while(!ready)@(posedge clk);
      @(negedge clk);in_valid=0;in_word=~value;in_rs=!command_data;
    end
  endtask
  task cancelled_word(input integer byte_phase);
    begin
      send_word(16'hface,byte_phase[0]);
      if(byte_phase<2)wait(!wr_n && !cs_n && bytes_in_cs==byte_phase);
      else wait(bytes_in_cs==2 && !cs_n);
      @(negedge clk);rst=1;in_valid=1;in_word=16'hdead;in_rs=1;
      #1;if(cs_n!==1 || wr_n!==1 || rd_n!==1 || ready!==0 || done!==0)
        $fatal(1,"reset must immediately make bus inactive");
      repeat(3)@(negedge clk);rst=0;in_valid=0;
      send_word(16'h1234+byte_phase,1);
      wait(ready);@(negedge clk);
    end
  endtask
  initial begin
    repeat(4)@(negedge clk);rst=0;
    send_word(16'h0000,0);send_word(16'hffff,1);send_word(16'h2c00,0);send_word(16'hf800,1);
    send_word(16'h07e0,1);send_word(16'h001f,1);send_word(16'h55aa,0);send_word(16'haa55,1);
    for(i=0;i<40;i=i+1)begin
      random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
      repeat(random_state[3:0])begin
        @(negedge clk);in_valid=0;in_word=random_state[31:16]^i;in_rs=random_state[4];
      end
      send_word(random_state[15:0],random_state[7]);
    end
    wait(ready);repeat(2)@(negedge clk);
    for(j=0;j<3;j=j+1)cancelled_word(j);
    // A sub-clock reset pulse must not let an interrupted word resume later.
    send_word(16'hbeef,1);wait(!wr_n && !cs_n && bytes_in_cs==0);
    @(negedge clk);#1;rst=1;in_valid=0;
    #1;if(cs_n!==1 || wr_n!==1 || rd_n!==1 || done!==0)$fatal(1,"short reset unsafe");
    #1;rst=0;
    repeat(20)begin @(negedge clk);if(!cs_n || !wr_n || done)$fatal(1,"cancelled word resumed after short reset");end
    send_word(16'h5678,1);
    wait(ready);repeat(3)@(negedge clk);
    if(accepted!=completed+cancelled || cancelled!=4 || read_index!=write_index || done || !cs_n || !wr_n)
      $fatal(1,"final bus accounting accepted=%0d done=%0d cancelled=%0d",accepted,completed,cancelled);
    $display("PASS nt35510_bus8 setup=%0d low=%0d hold=%0d gap=%0d accepted=%0d completed=%0d cancelled=%0d physical_bytes=%0d",
      SETUP_CYCLES,LOW_CYCLES,HOLD_CYCLES,GAP_CYCLES,accepted,completed,cancelled,bytes_seen);
    finished=1;
  end
  initial begin #100000;$fatal(1,"bus bench timeout");end
endmodule
module tb_nt35510_bus8;
  wire a,b;
  nt35510_bus8_case #(2,3,2,1) standard(a);
  nt35510_bus8_case #(2,2,1,0) minimum(b);
  initial begin wait(a && b);$display("PASS tb_nt35510_bus8 physical timing and reset");$finish;end
endmodule
module tb_nt35510_bus8_bad_setup;
  nt35510_bus8 #(.SETUP_CYCLES(1)) bad(.clk(1'b0),.rst(1'b1),.in_valid(1'b0),.in_word(16'b0),.in_rs(1'b0));
  initial begin #1;$fatal(1,"illegal setup was not rejected");end
endmodule
module tb_nt35510_bus8_bad_low;
  nt35510_bus8 #(.LOW_CYCLES(1)) bad(.clk(1'b0),.rst(1'b1),.in_valid(1'b0),.in_word(16'b0),.in_rs(1'b0));
  initial begin #1;$fatal(1,"illegal low was not rejected");end
endmodule
module tb_nt35510_bus8_bad_hold;
  nt35510_bus8 #(.HOLD_CYCLES(0)) bad(.clk(1'b0),.rst(1'b1),.in_valid(1'b0),.in_word(16'b0),.in_rs(1'b0));
  initial begin #1;$fatal(1,"illegal hold was not rejected");end
endmodule
module tb_nt35510_bus8_bad_gap;
  nt35510_bus8 #(.GAP_CYCLES(-1)) bad(.clk(1'b0),.rst(1'b1),.in_valid(1'b0),.in_word(16'b0),.in_rs(1'b0));
  initial begin #1;$fatal(1,"illegal gap was not rejected");end
endmodule
