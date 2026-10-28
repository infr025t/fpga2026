`timescale 1ns/1ps
// Independent source-side failure cases around the RAM/prefetch SOF delay.
// A failed, unaccepted source frame must be dropped before the core sees SOF;
// failures after acceptance instead invalidate exactly that accepted frame.
module runtime_early_error_case #(parameter integer L=55)(output reg finished=0);
  import video_runtime_pkg::*;
  localparam integer W=16,H=16;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,sv=0,sev=0;reg [63:0] token=0;
  source_end_t ending;frame_config_t config_value;
  wire cv,sof,eol,eof,abort,start,success,invalid;
  wire [7:0] pixel;wire [9:0] x;wire [8:0] y;
  wire [31:0] id,start_id,good_id,bad_id,seen,accepted,completed,bad,dropped;
  wire [3:0] reason,last;wire [8:0] sticky;
  reg [L:0] done_pipe=0;reg [31:0] id_pipe[0:L];integer d;
  ingress_guard #(W,H,L,200000,1024) dut(
    .clk(clk),.rst(rst),.source_valid(sv),.source_token(token),
    .source_end_valid(sev),.source_end(ending),.shadow_config(config_value),
    .stop_request(1'b0),.arithmetic_error(1'b0),
    .core_done_valid(done_pipe[L]),.core_done_frame_id(id_pipe[L]),.core_done_ok(1'b1),
    .core_valid(cv),.core_pixel(pixel),.core_x(x),.core_y(y),
    .core_sof(sof),.core_eol(eol),.core_eof(eof),.core_frame_id(id),.core_abort(abort),
    .frame_start_valid(start),.frame_start_id(start_id),
    .frame_success_valid(success),.frame_success_id(good_id),
    .frame_invalid_valid(invalid),.frame_invalid_id(bad_id),.frame_invalid_reason(reason),
    .seen_frames(seen),.accepted_frames(accepted),.completed_frames(completed),
    .invalid_frames(bad),.dropped_source(dropped),.last_reason(last),.sticky_errors(sticky));
  function automatic [7:0] expected_pixel(input [31:0] frame,input integer xx,yy);
    expected_pixel=frame+7*xx+11*yy;
  endfunction
  integer cycle=0,index=0,starts=0,goods=0,invalids=0,abort_edges=0;
  reg inflight=0,ended=0;reg [31:0] expected_id=0;
  always @(posedge clk)begin
    cycle=cycle+1;
    if(rst || abort)done_pipe<=0;
    else begin
      done_pipe<={done_pipe[L-1:0],cv && eof};id_pipe[0]<=id;
      for(d=1;d<=L;d=d+1)id_pipe[d]<=id_pipe[d-1];
    end
    if(rst)begin index=0;starts=0;goods=0;invalids=0;abort_edges=0;inflight=0;ended=0;end
    else begin
      if(abort)abort_edges=abort_edges+1;
      if(success)begin
        if(!inflight || !ended || good_id!==expected_id)$fatal(1,"L%0d premature/wrong success",L);
        inflight=0;goods=goods+1;
      end
      if(invalid)begin
        if(!inflight || bad_id!==expected_id)$fatal(1,"L%0d invalid has no matching accepted frame",L);
        inflight=0;invalids=invalids+1;
      end
      if(start)begin
        if(inflight || !cv || !sof || start_id!==id)$fatal(1,"L%0d accepted SOF contract",L);
        inflight=1;ended=0;index=0;expected_id=id;starts=starts+1;
      end
      if(cv)begin
        if(!inflight || id!==expected_id || x!==index%W || y!==index/W ||
           pixel!==expected_pixel(expected_id,index%W,index/W) || sof!==(index==0) ||
           eol!==(index%W==W-1) || eof!==(index==W*H-1))
          $fatal(1,"L%0d recovery raster mismatch index%0d",L,index);
        index=index+1;if(eof)ended=1;
      end
      if(!cv && (sof || eol || eof))$fatal(1,"L%0d marker without valid",L);
    end
  end
  task tick(input bit valid,input [63:0] value,input bit end_valid,input [31:0] fid,
            input bit ok,input [3:0] why);
    begin
      @(negedge clk);sv=valid;token=value;sev=end_valid;ending={fid,ok,why};
      @(posedge clk);#1;
    end
  endtask
  task idle(input integer count);
    integer n;begin for(n=0;n<count;n=n+1)tick(0,0,0,0,1,0);end
  endtask
  task reset_case;
    begin
      @(negedge clk);rst=1;sv=0;token=0;sev=0;ending=0;
      repeat(3)@(negedge clk);rst=0;
    end
  endtask
  task emit(input [31:0] fid,input integer n,input bit end_now);
    begin tick(1,pack_pixel(expected_pixel(fid,n%W,n/W),n%W,n/W,
      n==0,n%W==W-1,n==W*H-1,fid),end_now,fid,1,0);end
  endtask
  task finish_good(input integer wanted_accepted,wanted_bad,wanted_drop,wanted_seen);
    integer n;
    begin
      n=0;while(completed!=1 && n<L+32)begin idle(1);n=n+1;end
      idle(4);
      if(completed!=1 || accepted!=wanted_accepted || bad!=wanted_bad || dropped!=wanted_drop ||
         seen!=wanted_seen || accepted!=completed+bad || seen!=accepted+dropped || inflight ||
         dut.pending_starts!=0 || dut.prefetched!=0 || dut.fifo_level!=0)
        $fatal(1,"L%0d recovery/count identity seen=%0d acc=%0d done=%0d bad=%0d drop=%0d",L,seen,accepted,completed,bad,dropped);
    end
  endtask
  task recovery(input [31:0] fid,input integer wanted_accepted,wanted_bad,wanted_drop,wanted_seen);
    integer n;
    begin
      idle(4);
      for(n=0;n<W*H;n=n+1)emit(fid,n,n==W*H-1);
      finish_good(wanted_accepted,wanted_bad,wanted_drop,wanted_seen);
    end
  endtask
  integer cases=0,before_accept_cases=0,early_ok_cases=0,offset,r,n;
  task before_accept_failure(input integer delay_cycles,input bit ok,input [3:0] status_reason,wanted_reason);
    integer n;reg [31:0] fid;
    begin
      reset_case();fid=100+cases;
      if(delay_cycles==0)tick(1,pack_pixel(expected_pixel(fid,0,0),0,0,1,0,0,fid),1,fid,ok,status_reason);
      else begin
        emit(fid,0,0);idle(delay_cycles-1);tick(0,0,1,fid,ok,status_reason);
      end
      idle(5);
      if(seen!=1 || accepted || completed || bad || dropped!=1 || starts || invalids ||
         abort_edges!=1 || last!=wanted_reason || !sticky[wanted_reason])
        $fatal(1,"L%0d preaccept error delay%0d reason%0d lost seen=%0d acc=%0d bad=%0d drop=%0d last=%0d",L,delay_cycles,wanted_reason,seen,accepted,bad,dropped,last);
      recovery(900+cases,1,0,1,2);cases=cases+1;before_accept_cases=before_accept_cases+1;
    end
  endtask
  task before_accept_ok(input integer delay_cycles);
    integer n;reg [31:0] fid;
    begin
      reset_case();fid=4000+cases;
      for(n=0;n<W*H;n=n+1)begin
        if(n==delay_cycles)tick(1,pack_pixel(expected_pixel(fid,n%W,n/W),n%W,n/W,
          n==0,n%W==W-1,n==W*H-1,fid),1,fid,1,0);
        else emit(fid,n,0);
      end
      finish_good(1,0,0,1);
      if(abort_edges || sticky)$fatal(1,"L%0d early OK caused a false error",L);
      cases=cases+1;early_ok_cases=early_ok_cases+1;
    end
  endtask
  initial begin
    ending=0;config_value='0;config_value.epsilon=1024;
    config_value.threshold=2;config_value.gain=256;config_value.view_mode=2;
    // Four alignments: physical SOF itself, RAM, read response, core SOF edge.
    for(offset=0;offset<=3;offset=offset+1)before_accept_failure(offset,0,7,7);
    for(r=1;r<=8;r=r+1)before_accept_failure(r%4,0,r,r);
    // Invalid status metadata remains a protocol error, never an OK report.
    before_accept_failure(0,1,4,3);
    before_accept_failure(1,0,0,3);
    before_accept_failure(3,0,9,3);
    // The next synchronization SOF can fail immediately too. Its end event
    // must not disappear just because the guard was waiting in RECOVER.
    reset_case();
    tick(1,pack_pixel(expected_pixel(3000,0,0),0,0,1,0,0,3000),1,3000,0,7);idle(5);
    tick(1,pack_pixel(expected_pixel(3001,0,0),0,0,1,0,0,3001),1,3001,0,8);idle(5);
    if(seen!=2 || accepted || completed || bad || dropped!=2 || starts || invalids ||
       abort_edges!=2 || last!=8 || !sticky[7] || !sticky[8])
      $fatal(1,"L%0d consecutive early errors lost seen=%0d acc=%0d bad=%0d drop=%0d last=%0d",L,seen,accepted,bad,dropped,last);
    recovery(3002,1,0,2,3);cases=cases+1;before_accept_cases=before_accept_cases+1;
    // A stray failure with no observed SOF cannot invent a dropped frame.
    reset_case();tick(0,0,1,32'd999,0,7);idle(6);
    if(seen || accepted || completed || bad || dropped || sticky || abort_edges)
      $fatal(1,"L%0d idle stray error invented a frame",L);
    recovery(1000,1,0,0,1);cases=cases+1;
    // Once accepted, the same failure invalidates that frame exactly once.
    reset_case();for(n=0;n<20;n=n+1)emit(2000,n,0);
    tick(0,0,1,2000,0,7);idle(5);
    if(seen!=1 || accepted!=1 || bad!=1 || dropped || invalids!=1 || last!=7 || abort_edges!=1)
      $fatal(1,"L%0d accepted source-error accounting changed",L);
    recovery(2001,2,1,0,2);cases=cases+1;
    // A prebuffered source may already know capture status at the first token.
    // Preserve its OK even when the SOF is still in RAM or prefetch registers.
    for(offset=0;offset<=3;offset=offset+1)before_accept_ok(offset);
    reset_case();
    tick(1,pack_pixel(expected_pixel(5000,0,0),0,0,1,0,0,5000),1,5000,0,7);idle(5);
    tick(1,pack_pixel(expected_pixel(5001,0,0),0,0,1,0,0,5001),1,5001,1,0);
    for(n=1;n<W*H;n=n+1)emit(5001,n,0);
    finish_good(1,0,1,2);
    if(abort_edges!=1 || last!=7)$fatal(1,"L%0d recovery early OK caused another error",L);
    cases=cases+1;early_ok_cases=early_ok_cases+1;
    // The early status latch is not an excuse to accept duplicates or an ID
    // belonging to another frame. Both cases drop before accepted SOF.
    reset_case();
    tick(1,pack_pixel(expected_pixel(6000,0,0),0,0,1,0,0,6000),1,6000,1,0);
    tick(0,0,1,6000,1,0);idle(5);
    if(seen!=1 || accepted || bad || dropped!=1 || last!=3 || abort_edges!=1)
      $fatal(1,"L%0d duplicate early OK was not rejected",L);
    recovery(6001,1,0,1,2);cases=cases+1;before_accept_cases=before_accept_cases+1;
    reset_case();
    tick(1,pack_pixel(expected_pixel(7000,0,0),0,0,1,0,0,7000),1,7001,1,0);idle(6);
    if(seen!=1 || accepted || bad || dropped!=1 || last!=3 || abort_edges!=1)
      $fatal(1,"L%0d wrong-ID early OK was not rejected",L);
    recovery(7002,1,0,1,2);cases=cases+1;before_accept_cases=before_accept_cases+1;
    $display("PASS tb_runtime_early_error L=%0d cases=%0d before_accept=%0d early_ok=%0d complete_frames=%0d reasons1..8 offsets0..3 consecutive_failures protocol_metadata idle_stray accepted_failure",L,cases,before_accept_cases,early_ok_cases,cases);
    finished=1;
  end
  initial begin #5000000;$fatal(1,"early source-error watchdog L%0d",L);end
endmodule
module tb_runtime_early_error;
  wire a,b;
  runtime_early_error_case #(55) first(a);
  runtime_early_error_case #(56) second(b);
  initial begin wait(a && b);$display("PASS tb_runtime_early_error complete");$finish;end
endmodule
