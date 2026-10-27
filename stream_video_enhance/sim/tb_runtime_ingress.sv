`timescale 1ns/1ps
// Independent ingress contract scoreboard; no numerical-core implementation is
// copied here. A fake core only returns an EOF observation L+1 consumer edges
// after the exact final input token accepted by the guard.
module runtime_ingress_case #(parameter integer L=55)(output reg finished=0);
  import video_runtime_pkg::*;
  localparam integer W=16,H=16,N=W*H,DEPTH=1024,TIMEOUT=20000;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,sv=0,sev=0,stop=0,arith=0,auto_done=1,manual_done=0,manual_ok=1;
  reg [63:0] st=0;source_end_t se;frame_config_t cfg;
  reg [31:0] manual_id=0;
  wire cv,cs,cl,ce,ab,start,success,invalid,ready;
  wire [7:0] cp;wire [9:0] cx;wire [8:0] cy;wire [31:0] cid,sid,goodid,badid;
  wire [3:0] why;frame_config_t active;
  wire [31:0] seen,accepted,completed,bad,dropped,overflows,cfgerrors;
  wire [10:0] highwater,level;wire almost;wire [8:0] sticky;wire [3:0] last;
  reg [L:0] done_pipe=0;reg [31:0] id_pipe[0:L];integer d;
  wire dv=manual_done || (auto_done && done_pipe[L]);
  wire [31:0] did=manual_done?manual_id:id_pipe[L];
  ingress_guard #(W,H,L,200000,DEPTH) dut(
    .clk(clk),.rst(rst),.source_valid(sv),.source_token(st),.source_end_valid(sev),.source_end(se),
    .shadow_config(cfg),.stop_request(stop),.arithmetic_error(arith),
    .core_done_valid(dv),.core_done_frame_id(did),.core_done_ok(!manual_done || manual_ok),
    .core_valid(cv),.core_pixel(cp),.core_x(cx),.core_y(cy),.core_sof(cs),.core_eol(cl),.core_eof(ce),
    .core_frame_id(cid),.core_abort(ab),.active_config(active),.frame_start_valid(start),.frame_start_id(sid),
    .frame_success_valid(success),.frame_success_id(goodid),.frame_invalid_valid(invalid),
    .frame_invalid_id(badid),.frame_invalid_reason(why),.source_ready(ready),
    .seen_frames(seen),.accepted_frames(accepted),.completed_frames(completed),.invalid_frames(bad),
    .dropped_source(dropped),.overflow_count(overflows),.cfg_error(cfgerrors),
    .fifo_highwater(highwater),.fifo_level(level),.almost_full_seen(almost),.sticky_errors(sticky),.last_reason(last));
  always @(posedge clk)begin
    if(rst || ab)done_pipe<=0;
    else begin
      done_pipe<={done_pipe[L-1:0],cv && ce};id_pipe[0]<=cid;
      for(d=1;d<=L;d=d+1)id_pipe[d]<=id_pipe[d-1];
    end
  end
  function automatic [7:0] pix(input [31:0] f,input integer x,y);
    pix=f+7*x+11*y;
  endfunction
  function automatic frame_config_t legal_cfg(input integer number);
    frame_config_t c;
    begin c='0;c.epsilon=1024;c.threshold=4;c.gain=428;c.view_mode=3;
      c.cfg_id=number;c.profile_id=1;c.source_kind=1;c.pattern_id=2;
      c.preview_enable=number%2;c.roi_pair=(number/2)%2;legal_cfg=c;end
  endfunction
  function automatic valid_cfg(input frame_config_t c);
    valid_cfg=(c.epsilon==16 || c.epsilon==64 || c.epsilon==256 || c.epsilon==1024) &&
      c.threshold<=16 && c.gain<=512 && (c.view_mode!=2 || c.gain==256) && (c.view_mode>=2 || c.gain==0);
  endfunction
  integer index=0,cycles=0,starts=0,goods=0,invalids=0,simultaneous=0;
  reg inflight=0,last_input=0;reg [31:0] expected_id=0;
  frame_config_t last_config,frame_config;
  always @(posedge clk)begin
    cycles=cycles+1;
    if(rst)begin
      index=0;inflight=0;last_input=0;starts=0;goods=0;invalids=0;simultaneous=0;
      last_config='0;last_config.epsilon=1024;last_config.threshold=2;
      last_config.gain=256;last_config.view_mode=2;last_config.profile_id=1;
    end else begin
      if(success)begin
        if(!inflight || !last_input || goodid!==expected_id)$fatal(1,"L%0d success without exact complete input",L);
        inflight=0;goods=goods+1;
      end
      if(invalid)begin
        if(!inflight || badid!==expected_id || why==0 || why>8)$fatal(1,"L%0d invalid association",L);
        inflight=0;invalids=invalids+1;
      end
      if(start)begin
        if(inflight || !cv || !cs || sid!==cid)$fatal(1,"L%0d SOF acceptance contract",L);
        expected_id=cid;index=0;inflight=1;last_input=0;starts=starts+1;
        if(valid_cfg(cfg))last_config=cfg;
        frame_config=last_config;
        if(active!==frame_config)$fatal(1,"L%0d SOF config bypass/latching",L);
        if(success)simultaneous=simultaneous+1;
      end
      if(cv)begin
        if(!inflight || cid!==expected_id || cx!==index%W || cy!==index/W ||
           cp!==pix(expected_id,index%W,index/W) || cs!==(index==0) ||
           cl!==(index%W==W-1) || ce!==(index==N-1) || active!==frame_config)
          $fatal(1,"L%0d token/config mismatch index=%0d xy=%0d,%0d id=%0d pixel=%0d",L,index,cx,cy,cid,cp);
        index=index+1;
        if(ce)last_input=1;
      end
      if(!cv && (cs || cl || ce))$fatal(1,"marker without valid");
      if(dut.prefetched>2 || level>DEPTH)$fatal(1,"prefetch/FIFO capacity exceeded");
    end
  end
  task tick(input bit v,input [63:0] token,input bit ev,input [31:0] ef,input bit ok,input [3:0] reason);
    begin @(negedge clk);sv=v;st=token;sev=ev;se={ef,ok,reason};@(posedge clk);#1;end
  endtask
  task idle(input integer count);
    integer k;begin for(k=0;k<count;k=k+1)tick(0,0,0,0,1,0);end
  endtask
  task reset_case;
    begin @(negedge clk);rst=1;sv=0;st=0;sev=0;se=0;stop=0;arith=0;
      auto_done=1;manual_done=0;manual_ok=1;cfg=legal_cfg(1);
      repeat(3)@(posedge clk);@(negedge clk);rst=0;end
  endtask
  task emit(input [31:0] f,input integer i,input integer corruption,input bit ending);
    reg [63:0] token;
    begin token=pack_pixel(pix(f,i%W,i/W),i%W,i/W,i==0,i%W==W-1,i==N-1,f);
      case(corruption)
        1:token[17:8]=token[17:8]+1'b1;
        2:token[28]=!token[28];
        3:token[29]=!token[29];
        4:token[61:30]=f+1'b1;
        5:token[63]=1;
        6:token[62]=1;
        7:token[27]=1;
        8:token[29]=0;
        9:token[26:18]=token[26:18]+1'b1;
        default:begin end
      endcase
      tick(1,token,ending && i==N-1,f,1,0);
    end
  endtask
  task frame(input [31:0] f,input integer corruption,input bit ending);
    integer i;begin for(i=0;i<N;i=i+1)emit(f,i,
      ((corruption==8 && i==N-1) || (corruption!=8 && i==50))?corruption:0,ending);end
  endtask
  task wait_good(input integer target);
    integer k;begin k=0;while(completed<target && k<3*N+L+20)begin idle(1);k=k+1;end
      if(completed!==target)$fatal(1,"L%0d completed timeout got=%0d target=%0d reason=%0d",L,completed,target,last);end
  endtask
  task wait_bad(input integer target,input integer reason);
    integer k;begin k=0;while(bad<target && k<TIMEOUT+N+L+200)begin idle(1);k=k+1;end
      if(bad!==target || last!==reason || !sticky[reason])
        $fatal(1,"L%0d invalid mismatch bad=%0d target=%0d last=%0d reason=%0d",L,bad,target,last,reason);end
  endtask
  task identities;
    begin idle(L+12);
      if(accepted!==completed+bad || seen!==accepted+dropped || dut.pending_starts!=0 || inflight)
        $fatal(1,"L%0d quiescent counters seen=%0d acc=%0d good=%0d bad=%0d drop=%0d pending=%0d",L,seen,accepted,completed,bad,dropped,dut.pending_starts);
    end
  endtask
  task recovery(input integer expected_good);
    begin idle(4);cfg=legal_cfg(2);frame(32'd900,0,1);wait_good(expected_good);identities();end
  endtask
  task overflow_case;
    integer i;begin auto_done=0;frame(32'd21,0,0);
      for(i=0;i<DEPTH+16;i=i+1)tick(1,pack_pixel(0,0,0,0,0,0,21),0,0,1,0);
      wait_bad(1,2);
      if(overflows!=1 || !almost || highwater!=DEPTH)$fatal(1,"real full/threshold evidence missing");
      auto_done=1;recovery(1);
    end
  endtask
  integer c,i,r,base,guardcases=0;
  initial begin
    se=0;cfg=legal_cfg(1);
    reset_case();
    // Accepted SOF samples the current shadow, not the bus at physical ingress.
    emit(10,0,0,0);cfg=legal_cfg(17);
    for(i=1;i<N;i=i+1)begin emit(10,i,0,1);if(i==25)cfg=legal_cfg(42);end
    wait_good(1);cfg=legal_cfg(2);frame(11,0,1);wait_good(2);identities();guardcases=guardcases+1;
    // Both valid frame IDs across wrap are legal; sequence numbers do not saturate.
    reset_case();frame(32'hffffffff,0,1);wait_good(1);frame(0,0,1);wait_good(2);identities();guardcases=guardcases+1;
    // Every malformed accepted raster is rejected exactly once and can recover.
    for(c=1;c<=9;c=c+1)begin
      reset_case();frame(32'd30,c,1);wait_bad(1,3);recovery(1);guardcases=guardcases+1;
    end
    reset_case();for(i=0;i<20;i=i+1)emit(31,i,0,0);
    tick(0,pack_pixel(0,0,0,1,0,0,31),0,0,1,0);
    wait_bad(1,3);recovery(1);guardcases=guardcases+1;
    // Source error reasons are independent from the finite pixel FIFO.
    for(r=1;r<=8;r=r+1)begin
      reset_case();for(i=0;i<20;i=i+1)emit(40+r,i,0,0);
      tick(0,0,1,40+r,0,r);wait_bad(1,r);recovery(1);guardcases=guardcases+1;
    end
    reset_case();for(i=0;i<20;i=i+1)emit(50,i,0,0);
    tick(0,0,1,51,1,0);wait_bad(1,3);recovery(1);guardcases=guardcases+1;
    reset_case();for(i=0;i<20;i=i+1)emit(51,i,0,0);
    tick(0,0,1,51,1,0);tick(0,0,1,51,1,0);wait_bad(1,3);recovery(1);guardcases=guardcases+1;
    reset_case();for(i=0;i<20;i=i+1)emit(54,i,0,0);
    tick(0,0,1,54,1,4);wait_bad(1,3);recovery(1);guardcases=guardcases+1;
    reset_case();for(i=0;i<20;i=i+1)emit(52,i,0,0);
    @(negedge clk);arith=1;tick(0,0,0,0,1,0);arith=0;
    wait_bad(1,6);recovery(1);guardcases=guardcases+1;
    reset_case();for(i=0;i<20;i=i+1)emit(53,i,0,0);
    @(negedge clk);manual_done=1;manual_id=53;manual_ok=1;tick(0,0,0,0,1,0);manual_done=0;
    wait_bad(1,3);recovery(1);guardcases=guardcases+1;
    reset_case();auto_done=0;frame(55,0,1);idle(L+12);
    @(negedge clk);manual_done=1;manual_id=56;manual_ok=1;tick(0,0,0,0,1,0);manual_done=0;
    wait_bad(1,3);auto_done=1;recovery(1);guardcases=guardcases+1;
    reset_case();auto_done=0;frame(56,0,1);idle(L+12);
    @(negedge clk);manual_done=1;manual_id=56;manual_ok=0;tick(0,0,0,0,1,0);manual_done=0;
    wait_bad(1,3);auto_done=1;recovery(1);guardcases=guardcases+1;
    reset_case();emit(57,0,1,0);idle(12);
    if(accepted || bad || seen!=1 || dropped!=1 || last!=3)$fatal(1,"malformed first SOF incorrectly accepted/counted");
    recovery(1);guardcases=guardcases+1;
    // Source OK before and after the independently observed core EOF.
    reset_case();for(i=0;i<N;i=i+1)begin
      if(i==20)tick(0,0,1,60,1,0);emit(60,i,0,0);end
    wait_good(1);frame(61,0,0);idle(L+15);
    if(completed!=1)$fatal(1,"source OK was not required");
    tick(0,0,1,61,1,0);wait_good(2);identities();guardcases=guardcases+1;
    reset_case();frame(62,0,0);wait_bad(1,5);recovery(1);guardcases=guardcases+1;
    reset_case();frame(63,0,0);emit(64,0,0,0);wait_bad(1,3);
    if(dropped!=1)$fatal(1,"queued SOF missing-end budget did not drop queued frame");
    recovery(1);guardcases=guardcases+1;
    // Stop completes the accepted frame, drops future source frames and resumes.
    reset_case();for(i=0;i<N;i=i+1)begin emit(70,i,0,1);if(i==128)stop=1;end
    wait_good(1);frame(71,0,1);idle(L+12);
    if(accepted!=1 || bad!=0 || completed!=1 || dropped!=1)$fatal(1,"stop cut current or accepted future frame");
    stop=0;recovery(2);guardcases=guardcases+1;
    reset_case();overflow_case();guardcases=guardcases+1;
    // Invalid configuration retains the last valid whole-frame snapshot.
    reset_case();cfg.epsilon=3;frame(80,0,1);wait_good(1);
    cfg=legal_cfg(8);cfg.view_mode=0;cfg.gain=428;frame(81,0,1);wait_good(2);
    if(cfgerrors!=2)$fatal(1,"illegal config fallback/count");identities();guardcases=guardcases+1;
    // Reset with an active accepted frame flushes both prefetch and delayed done.
    reset_case();for(i=0;i<100;i=i+1)emit(90,i,0,0);
    reset_case();frame(91,0,1);wait_good(1);identities();guardcases=guardcases+1;
    // Shared saturated add and actual repeated frame counters saturate, IDs wrap.
    if(sat_add(32'hfffffffe,33'd1)!==32'hffffffff ||
       sat_add(32'hffffffff,33'd1)!==32'hffffffff ||
       sat_add(32'd7,33'h1ffffffff)!==32'hffffffff)$fatal(1,"saturated counter arithmetic");
    reset_case();@(negedge clk);dut.seen_frames=32'hfffffffe;dut.accepted_frames=32'hfffffffe;dut.completed_frames=32'hfffffffe;
    frame(32'hffffffff,0,1);idle(L+15);frame(0,0,1);idle(L+15);
    if(seen!==32'hffffffff || accepted!==32'hffffffff || completed!==32'hffffffff)
      $fatal(1,"actual frame counters wrapped instead of saturated");
    @(negedge clk);dut.invalid_frames=32'hfffffffe;
    frame(101,1,1);idle(L+15);frame(102,9,1);idle(L+15);
    if(bad!==32'hffffffff)$fatal(1,"invalid counter failed saturation");
    @(negedge clk);dut.cfg_error=32'hfffffffe;cfg.epsilon=3;
    frame(103,0,1);idle(L+15);frame(104,0,1);idle(L+15);
    if(cfgerrors!==32'hffffffff)$fatal(1,"configuration counter failed saturation");
    @(negedge clk);dut.dropped_source=32'hfffffffe;stop=1;
    idle(4);emit(105,0,0,0);emit(106,0,0,0);idle(4);stop=0;
    if(dropped!==32'hffffffff)$fatal(1,"dropped counter failed saturation");
    @(negedge clk);dut.overflow_count=32'hfffffffe;auto_done=0;
    for(c=0;c<2;c=c+1)begin
      frame(107+c,0,0);
      for(i=0;i<DEPTH+16;i=i+1)tick(1,pack_pixel(0,0,0,0,0,0,107+c),0,0,1,0);
      idle(L+15);
    end
    if(overflows!==32'hffffffff)$fatal(1,"overflow counter failed saturation");guardcases=guardcases+1;
    $display("PASS tb_runtime_ingress L=%0d directed_cases=%0d",L,guardcases);finished=1;
  end
  initial begin #20000000;$fatal(1,"ingress directed timeout L=%0d",L);end
endmodule

module runtime_pattern_case #(parameter integer W=16,H=16,L=55,PATTERN=0,FRAMES=4)(output reg finished=0);
  import video_runtime_pkg::*;
  reg clk=0;always #5 clk=~clk;reg rst=1,enable=0;
  wire sv,sev,cv,cs,cl,ce,ab,start,success,invalid;wire [63:0] token;
  source_end_t source_end;frame_config_t cfg,active;
  wire [7:0] pixel;wire [9:0] x;wire [8:0] y;wire [31:0] id,seen,accepted,completed,bad,dropped;
  wire [10:0] level,highwater;wire [31:0] sid;
  reg [L:0] done_pipe=0;reg [31:0] id_pipe[0:L];integer d;
  source_pattern #(W,H,PATTERN,L) source(clk,rst,enable,sv,token,sev,source_end);
  ingress_guard #(W,H,L,100000000,1024) dut(
    .clk(clk),.rst(rst),.source_valid(sv),.source_token(token),.source_end_valid(sev),.source_end(source_end),
    .shadow_config(cfg),.stop_request(1'b0),.arithmetic_error(1'b0),
    .core_done_valid(done_pipe[L]),.core_done_frame_id(id_pipe[L]),.core_done_ok(1'b1),
    .core_valid(cv),.core_pixel(pixel),.core_x(x),.core_y(y),.core_sof(cs),.core_eol(cl),.core_eof(ce),
    .core_frame_id(id),.core_abort(ab),.active_config(active),.frame_start_valid(start),.frame_start_id(sid),
    .frame_success_valid(success),.frame_invalid_valid(invalid),
    .seen_frames(seen),.accepted_frames(accepted),.completed_frames(completed),.invalid_frames(bad),
    .dropped_source(dropped),.fifo_level(level),.fifo_highwater(highwater));
  function automatic [7:0] expected(input integer px,py,input [31:0] f);
    case(PATTERN)0:expected=px+py+f;1:expected=(((px/16)+(py/16))%2==0)?32:224;
      2:expected=(2*px<W)?32:224;default:expected=128;endcase
  endfunction
  integer physical=0,outputs=0,index=0,cycle=0,last_eof=0,simultaneous=0,max_level=0;
  integer last_peak=0,steady_peak=0;reg [31:0] expected_id=0;
  always @(posedge clk)begin
    cycle=cycle+1;
    if(rst || ab)done_pipe<=0;
    else begin done_pipe<={done_pipe[L-1:0],cv && ce};id_pipe[0]<=id;
      for(d=1;d<=L;d=d+1)id_pipe[d]<=id_pipe[d-1];end
    if(!rst)begin
      if(sv)begin
        if(token[7:0]!==expected(token[17:8],token[26:18],token[61:30]))$fatal(1,"pattern source numerical mismatch");
        if(token[27] && physical!=0 && cycle-last_eof!=L+1)$fatal(1,"pattern source frame gap");
        if(token[29])begin
          if(!sev || source_end!=={token[61:30],1'b1,4'd0})$fatal(1,"pattern source end association");
          physical=physical+1;last_eof=cycle;
        end
      end
      if(cv)begin
        if(id!==expected_id || x!==index%W || y!==index/W || pixel!==expected(index%W,index/W,expected_id) ||
           cs!==(index==0) || cl!==(index%W==W-1) || ce!==(index==W*H-1))$fatal(1,"pattern guard dropped/reordered token");
        if(ce)begin index=0;expected_id=expected_id+1'b1;end else index=index+1;
        outputs=outputs+1;
      end
      if(success && start)simultaneous=simultaneous+1;
      if(invalid || ab)$fatal(1,"normal pattern invalid/abort");
      if(level>max_level)max_level=level;
      if(physical>=2 && level>steady_peak)steady_peak=level;
    end
  end
  initial begin
    cfg='0;cfg.epsilon=1024;cfg.threshold=2;cfg.gain=256;cfg.view_mode=2;
    repeat(4)@(negedge clk);rst=0;enable=1;
    // Removing enable mid-frame must retain its remaining pixels and source OK.
    wait(physical==FRAMES-1 && source.x==W/2 && source.y==H/2);@(negedge clk);enable=0;
    wait(completed==FRAMES);repeat(L+16)@(negedge clk);
    if(physical!=FRAMES || accepted!=FRAMES || seen!=FRAMES || bad || dropped || index || outputs!=FRAMES*W*H)
      $fatal(1,"pattern final counts");
    if(max_level>12 || steady_peak>12)$fatal(1,"pattern occupancy accumulated peak=%0d steady=%0d",max_level,steady_peak);
    $display("PASS tb_runtime_pattern W=%0d H=%0d L=%0d pattern=%0d frames=%0d tokens=%0d peak=%0d steady_peak=%0d same_edge_handoffs=%0d",W,H,L,PATTERN,FRAMES,outputs,max_level,steady_peak,simultaneous);
    finished=1;
  end
  initial begin #1000000000;$fatal(1,"pattern runtime timeout");end
endmodule

module tb_runtime_ingress;
  wire a,b,c,d,e,f,g,h,j,k;
  runtime_ingress_case #(55) first(a);
  runtime_ingress_case #(56) second(b);
  runtime_pattern_case #(16,16,55,0,10) p0(c);
  runtime_pattern_case #(16,16,56,1,4) p1(d);
  runtime_pattern_case #(16,16,55,2,4) p2(e);
  runtime_pattern_case #(16,16,56,3,4) p3(f);
  runtime_external_case #(0,55) e0(g);
  runtime_external_case #(1,56) e1(h);
  runtime_external_case #(2,55) e2(j);
  runtime_external_case #(3,56) e3(k);
  initial begin wait(a && b && c && d && e && f && g && h && j && k);$display("PASS tb_runtime_ingress complete");$finish;end
endmodule

// External envelope: one source pixel every four 100 MHz cycles, no added
// inter-frame gap, and independent source OK withheld for 128 cycles after EOF.
// Thus the next physical SOF waits for the previous frame, stressing S_FRAME
// almost to its deadline; this is a logical envelope, not camera/CDC validation.
module runtime_external_case #(parameter integer PHASE=0,L=55)(output reg finished=0);
  import video_runtime_pkg::*;
  localparam integer W=16,H=16,FRAMES=10,END_DELAY=128,BUDGET=40;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,sv=0,sev=0;reg [63:0] token=0;
  source_end_t se;frame_config_t cfg,active;
  wire cv,cs,cl,ce,ab,start,success,invalid;wire [7:0] pixel;
  wire [9:0] x;wire [8:0] y;wire [31:0] id,start_id;
  wire [31:0] seen,accepted,completed,bad,dropped;
  wire [10:0] highwater,level;
  reg [L:0] done_pipe=0;reg [31:0] id_pipe[0:L];integer d;
  ingress_guard #(W,H,L,100000000,1024) dut(
    .clk(clk),.rst(rst),.source_valid(sv),.source_token(token),.source_end_valid(sev),.source_end(se),
    .shadow_config(cfg),.stop_request(1'b0),.arithmetic_error(1'b0),
    .core_done_valid(done_pipe[L]),.core_done_frame_id(id_pipe[L]),.core_done_ok(1'b1),
    .core_valid(cv),.core_pixel(pixel),.core_x(x),.core_y(y),.core_sof(cs),.core_eol(cl),.core_eof(ce),
    .core_frame_id(id),.core_abort(ab),.active_config(active),.frame_start_valid(start),.frame_start_id(start_id),
    .frame_success_valid(success),.frame_invalid_valid(invalid),
    .seen_frames(seen),.accepted_frames(accepted),.completed_frames(completed),.invalid_frames(bad),
    .dropped_source(dropped),.fifo_highwater(highwater),.fifo_level(level));
  function automatic [7:0] expected(input integer xx,yy,ff);
    expected=ff+7*xx+11*yy;
  endfunction
  integer cycle=0,source_frame=0,source_index=0,end_due=0,end_id=0;
  integer expected_id=0,index=0,tokens=0,max_wait=0,source_spacing=0,last_source=0;
  integer arrival[0:FRAMES-1];reg end_pending=0;
  always @(negedge clk)begin
    sv=0;token=0;sev=0;
    if(!rst)begin
      if(source_frame<FRAMES && cycle%4==PHASE)begin
        sv=1;token=pack_pixel(expected(source_index%W,source_index/W,source_frame),
          source_index%W,source_index/W,source_index==0,source_index%W==W-1,source_index==W*H-1,source_frame);
        if(source_index==W*H-1)begin
          if(end_pending)$fatal(1,"external end mailbox test generator overrun");
          end_pending=1;end_due=cycle+END_DELAY;end_id=source_frame;
          source_index=0;source_frame=source_frame+1;
        end else source_index=source_index+1;
      end
      if(end_pending && cycle==end_due)begin sev=1;se={32'(end_id),1'b1,4'd0};end_pending=0;end
    end
  end
  always @(posedge clk)begin
    cycle=cycle+1;
    if(rst || ab)done_pipe<=0;
    else begin done_pipe<={done_pipe[L-1:0],cv && ce};id_pipe[0]<=id;
      for(d=1;d<=L;d=d+1)id_pipe[d]<=id_pipe[d-1];end
    if(!rst)begin
      if(sv)begin
        if(last_source!=0 && cycle-last_source!=4)$fatal(1,"external source violated its own 4-cycle envelope");
        last_source=cycle;
        if(token[27])arrival[token[61:30]]=cycle;
      end
      if(start)begin
        if(cycle-arrival[start_id]>max_wait)max_wait=cycle-arrival[start_id];
        if(cycle-arrival[start_id]>=128)$fatal(1,"external queued SOF exceeded handoff budget");
      end
      if(cv)begin
        if(id!==32'(expected_id) || x!==index%W || y!==index/W || pixel!==expected(index%W,index/W,expected_id) ||
           cs!==(index==0) || cl!==(index%W==W-1) || ce!==(index==W*H-1))
          $fatal(1,"external source lost raster/data/frame association");
        tokens=tokens+1;
        if(ce)begin index=0;expected_id=expected_id+1;end else index=index+1;
      end
      if(invalid || ab)$fatal(1,"legal external envelope aborted");
      if(highwater>BUDGET)$fatal(1,"external FIFO highwater=%0d exceeds ceil(S_FRAME/4)+8",highwater);
    end
  end
  initial begin
    se=0;cfg='0;cfg.epsilon=1024;cfg.threshold=2;cfg.gain=0;cfg.view_mode=0;
    repeat(4)@(posedge clk);#1;rst=0;
    wait(completed==FRAMES);repeat(L+12)@(negedge clk);
    if(accepted!=FRAMES || seen!=FRAMES || bad || dropped || index || level || dut.prefetched || tokens!=FRAMES*W*H)
      $fatal(1,"external envelope final counters/capacity");
    $display("PASS tb_runtime_external phase=%0d L=%0d frames=%0d tokens=%0d highwater=%0d budget=%0d max_handoff=%0d",PHASE,L,FRAMES,tokens,highwater,BUDGET,max_wait);
    finished=1;
  end
  initial begin #2000000;$fatal(1,"external envelope timeout");end
endmodule
module tb_runtime_ingress_vga;
  wire a,b;
  runtime_pattern_case #(640,480,55,0,10) first(a);
  runtime_pattern_case #(640,480,56,2,10) second(b);
  initial begin wait(a && b);$display("PASS tb_runtime_ingress_vga complete");$finish;end
endmodule
