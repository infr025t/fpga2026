`timescale 1ns/1ps
module tb_nt35510_init;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,word_ready=0,word_done=0;
  wire word_valid,word_rs,lcd_reset_n,init_done;
  wire [15:0] word;
  nt35510_init #(.CLK_HZ(1000)) dut(
    .clk(clk),.rst(rst),.word_ready(word_ready),.word_done(word_done),
    .word_valid(word_valid),.word(word),.word_rs(word_rs),
    .lcd_reset_n(lcd_reset_n),.init_done(init_done));
  // Constant-only probes catch 32-bit overflow and nonintegral-clock rounding.
  nt35510_init default_probe(.clk(1'b0),.rst(1'b1),.word_ready(1'b0),.word_done(1'b0));
  nt35510_init #(.CLK_HZ(1001)) ceiling_probe(
    .clk(1'b0),.rst(1'b1),.word_ready(1'b0),.word_done(1'b0));
  reg [16:0] expected[0:731];
  reg pending=0,stalled=0,sleep_seen=0,post_sleep_seen=0;
  reg first_word_seen=0,previous_reset=0,previous_done=0;
  reg [16:0] held_word;
  reg [15:0] random_state=16'hc0de;
  integer delay_left=0,forced_stall_left=8;
  integer cycle=0,last_reset_cycle=0,release_cycle=0,sleep_done_cycle=0;
  integer accepted=0,completed=0,total_accepted=0,complete_sessions=0;
  integer stalls=0,forced_stalls=0;
  string directory;

  // A word consumer: random stalls before acceptance and variable independent
  // completion latency afterwards. ready is deliberately low on the done edge.
  always @(negedge clk)begin
    random_state={random_state[14:0],random_state[15]^random_state[13]^random_state[12]^random_state[10]};
    word_done=0;
    if(rst)begin word_ready=0;pending=0;delay_left=0;forced_stall_left=8;end
    else if(pending)begin
      word_ready=0;
      if(delay_left==0)begin word_done=1;pending=0;end
      else delay_left=delay_left-1;
    end else if(accepted==17 && forced_stall_left!=0)begin
      word_ready=0;forced_stall_left=forced_stall_left-1;forced_stalls=forced_stalls+1;
    end else word_ready=random_state[0] || random_state[3];
  end

  always @(posedge clk)begin
    cycle=cycle+1;
    if(rst)begin
      accepted=0;completed=0;stalled=0;sleep_seen=0;post_sleep_seen=0;
      first_word_seen=0;previous_reset=0;previous_done=0;last_reset_cycle=cycle;
      pending=0;
    end else begin
      if(stalled && (!word_valid || {word_rs,word}!==held_word))
        $fatal(1,"init payload changed while waiting for ready");
      stalled=word_valid && !word_ready;
      if(stalled)begin held_word={word_rs,word};stalls=stalls+1;end
      if(word_valid && word_ready)begin
        if(pending || accepted>=732)$fatal(1,"init sent overlapping/extra word");
        if({word_rs,word}!==expected[accepted])
          $fatal(1,"init word %0d got=%h want=%h",accepted,{word_rs,word},expected[accepted]);
        if(!lcd_reset_n)$fatal(1,"word sent while LCD reset asserted");
        accepted=accepted+1;total_accepted=total_accepted+1;
        pending=1;delay_left=random_state[6:4]+1;
      end
      if(word_done)begin
        if(completed>=accepted)$fatal(1,"test consumer produced an unowned completion");
        if(expected[completed]==17'h01100)begin sleep_seen=1;sleep_done_cycle=cycle;end
        completed=completed+1;
      end
    end
    #1;
    if(rst)begin
      if(word_valid || lcd_reset_n || init_done)$fatal(1,"reset did not mask init interface");
    end else begin
      if(lcd_reset_n && !previous_reset)begin
        release_cycle=cycle;
        if(cycle-last_reset_cycle!=20)$fatal(1,"LCD reset duration off by a clock");
      end
      if(word_valid && !first_word_seen)begin
        first_word_seen=1;
        if(cycle-release_cycle!=120)$fatal(1,"release-to-first-valid wait off by a clock");
      end
      if(sleep_seen && word_valid && !post_sleep_seen)begin
        post_sleep_seen=1;
        if(cycle-sleep_done_cycle!=120 || {word_rs,word}!==17'h02900)
          $fatal(1,"Sleep Out did not wait exactly the policy cycles before Display On");
      end
      if(init_done && !previous_done)begin
        if(accepted!=732 || completed!=732 || pending || word_valid)
          $fatal(1,"init_done before the final data word completed");
        complete_sessions=complete_sessions+1;
      end
      if(previous_done && (!init_done || word_valid))$fatal(1,"init completion was not sticky");
      previous_reset=lcd_reset_n;previous_done=init_done;
    end
  end

  task reset_session;
    begin
      @(negedge clk);rst=1;
      #1;if(word_valid || lcd_reset_n || init_done)$fatal(1,"reset masking is not immediate");
      repeat(3)@(negedge clk);
      rst=0;
    end
  endtask

  initial begin
    if(!$value$plusargs("VECTORS=%s",directory))$fatal(1,"missing initialization source vectors");
    $readmemh({directory,"/expected_init.hex"},expected);
    #1;
    if(default_probe.RESET_LOW_CYCLES!=64'd2000000 ||
       default_probe.RESET_WAIT_CYCLES!=64'd12000000 ||
       default_probe.SLEEP_WAIT_CYCLES!=64'd12000000)
      $fatal(1,"default clock/millisecond multiplication overflowed");
    if(ceiling_probe.RESET_LOW_CYCLES!=21 || ceiling_probe.RESET_WAIT_CYCLES!=121 ||
       ceiling_probe.SLEEP_WAIT_CYCLES!=121)$fatal(1,"wait rounding was not conservative");
    reset_session();
    wait(accepted==9);reset_session(); // Interrupt an in-flight word.
    wait(sleep_seen);repeat(7)@(negedge clk);reset_session(); // Interrupt the long wait.
    wait(complete_sessions==1);repeat(20)@(negedge clk);
    reset_session(); // A completed initializer must restart from command zero.
    wait(complete_sessions==2);repeat(20)@(negedge clk);
    if(accepted!=732 || completed!=732 || forced_stalls<24 || stalls<24 || !init_done)
      $fatal(1,"initialization coverage incomplete");
    $display("PASS tb_nt35510_init entries=367 words=732 complete_sessions=%0d total_words=%0d cycles=%0d stalls=%0d forced_stalls=%0d reset/release/sleep/default64bit/rounding/restart",
      complete_sessions,total_accepted,cycle,stalls,forced_stalls);
    $finish;
  end
  initial begin repeat(100000)@(posedge clk);$fatal(1,"initializer bench timed out");end
endmodule
