`timescale 1ns/1ps
// Actual numerical core, independently generated fixed-model pixels/zlib CRCs.
// Malformed-frame prefixes may be visible; only the four good frames publish.
module tb_runtime_recovery #(parameter integer W=16,H=16,EXTRA_ALIGN=0);
 import video_runtime_pkg::*;
 localparam integer INPUTS=W*H,N=(W-8)*(H-8),L=core_latency_pkg::L_CORE+EXTRA_ALIGN;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,source_valid=0,source_end_valid=0;reg [63:0] source_token=0;
 source_end_t source_end;frame_config_t shadow_config;
 wire latest_valid,claimed_valid,core_abort,start,success,invalid;
 wire [31:0] start_id,success_id,invalid_id;wire [3:0] invalid_reason;
 wire [31:0] seen,accepted,completed,bad,dropped,overflows,cfg_errors,overwrites;
 wire [10:0] highwater;wire [3:0] last_reason;
 wire [7:0] pixel,raw,base;wire valid,sof,eol,eof;wire [9:0] x;wire [8:0] y;wire [31:0] id;
 core_report_t latest,claimed;
 video_runtime #(W,H,EXTRA_ALIGN,200000) dut(
   .clk(clk),.rst(rst),.source_valid(source_valid),.source_token(source_token),
   .source_end_valid(source_end_valid),.source_end(source_end),.shadow_config(shadow_config),
   .stop_request(1'b0),.claim(1'b0),.latest_valid(latest_valid),.latest(latest),
   .claimed_valid(claimed_valid),.claimed_report(claimed),.core_abort(core_abort),
   .frame_start_valid(start),.frame_start_id(start_id),.frame_success_valid(success),.frame_success_id(success_id),
   .frame_invalid_valid(invalid),.frame_invalid_id(invalid_id),.frame_invalid_reason(invalid_reason),
   .out_pixel(pixel),.out_raw(raw),.out_base(base),.out_valid(valid),.out_x(x),.out_y(y),
   .out_sof(sof),.out_eol(eol),.out_eof(eof),.out_frame_id(id),
   .seen_frames(seen),.accepted_frames(accepted),.completed_frames(completed),.invalid_frames(bad),
   .dropped_source(dropped),.overflow_count(overflows),.cfg_error(cfg_errors),.overwrite_count(overwrites),
   .fifo_highwater(highwater),.last_reason(last_reason));
 reg [23:0] expected[0:4*N-1];reg [31:0] raw_crc[0:3],selected_crc[0:3];
 integer output_index[0:3],input_eof_cycle[0:3],output_eof_cycle[0:3];
 integer success_cycle[0:3],source_ok_cycle[0:3];
 integer cycle=0,reports=0,good_outputs=0,good_frames=0,invalid_events=0,abort_edges=0;
 integer bad_prefix=0,bad_full_count=0;reg bad_full_eof=0;
 integer last_seq=0,good_id,expected_bad,expected_accepted,k;
 string vectors,filename;core_report_t last_good;
 always @(posedge clk)begin
   cycle=cycle+1;
   if(rst)begin
     reports=0;good_outputs=0;good_frames=0;invalid_events=0;abort_edges=0;
     bad_prefix=0;bad_full_count=0;bad_full_eof=0;last_seq=0;
     for(k=0;k<4;k=k+1)begin
       output_index[k]=0;input_eof_cycle[k]=0;output_eof_cycle[k]=0;
       success_cycle[k]=0;source_ok_cycle[k]=0;
     end
   end else begin
     if(core_abort)begin
       abort_edges=abort_edges+1;
       if(dut.iv || start || success || valid)$fatal(1,"abort did not mask actual core/input events");
     end
     if(dut.iv && dut.eof && dut.fid<4)input_eof_cycle[dut.fid]=cycle;
     if(source_end_valid && source_end.ok && source_end.frame_id<4)
       source_ok_cycle[source_end.frame_id]=cycle;
     if(dut.done_valid && dut.done_id<4)output_eof_cycle[dut.done_id]=cycle;
     if(success)begin
       if(success_id>=4 || success_cycle[success_id]!=0)$fatal(1,"bad/repeated frame success id=%0d",success_id);
       success_cycle[success_id]=cycle;
     end
     if(invalid)begin
       if((invalid_id!=100 && invalid_id!=101 && invalid_id!=102) ||
          invalid_reason!==((invalid_id==102)?4'd4:4'd3))
         $fatal(1,"unexpected invalid id=%0d reason=%0d",invalid_id,invalid_reason);
       invalid_events=invalid_events+1;
     end
   end
   #1;
   if(!rst)begin
     if(overflows || cfg_errors)$fatal(1,"recovery introduced FIFO/config fault");
     if(valid)begin
       if(id<4)begin
         good_id=id;
         if(id!=good_frames || x!=4+output_index[good_id]%(W-8) ||
            y!=4+output_index[good_id]/(W-8) ||
            sof!==(output_index[good_id]==0) ||
            eol!==(output_index[good_id]%(W-8)==W-9) || eof!==(output_index[good_id]==N-1))
           $fatal(1,"recovered output raster id=%0d index=%0d xy=%0d,%0d",id,output_index[good_id],x,y);
         if({raw,base,pixel}!==expected[good_id*N+output_index[good_id]])
           $fatal(1,"recovered pixel id=%0d index=%0d got=%h want=%h",id,output_index[good_id],
             {raw,base,pixel},expected[good_id*N+output_index[good_id]]);
         output_index[good_id]=output_index[good_id]+1;good_outputs=good_outputs+1;
         if(eof)begin
           if(cycle-input_eof_cycle[good_id]!=L)$fatal(1,"recovered numeric latency");
           good_frames=good_frames+1;
         end
       end else if(id==101)begin
         bad_prefix=bad_prefix+1;if(eof)$fatal(1,"protocol-invalid frame completed output");
       end else if(id==102)begin
         bad_full_count=bad_full_count+1;if(eof)bad_full_eof=1;
       end else $fatal(1,"warmup/reset-invalid frame leaked output id=%0d",id);
     end
     if(latest_valid && latest.diagnostic_seq!=last_seq)begin
       good_id=reports;
       expected_bad=(good_id<3)?good_id+1:3;
       expected_accepted=(good_id<3)?2*(good_id+1):7;
       if(good_id>=4 || latest.diagnostic_seq!=reports+1 || latest.frame_id!=good_id ||
          latest.pixel_count!=N || latest.raw_crc!==raw_crc[good_id] ||
          latest.selected_crc!==selected_crc[good_id] || latest.frame_config.cfg_id!=100+good_id ||
          latest.frame_config.view_mode!=good_id || latest.frame_config.epsilon!=1024 ||
          latest.frame_config.threshold!=((good_id==2)?2:(good_id==3)?4:0) ||
          latest.frame_config.gain!=((good_id==2)?256:(good_id==3)?428:0) ||
          latest.completed_frames!=good_id+1 || latest.invalid_frames!=expected_bad ||
          latest.accepted_frames!=expected_accepted || cycle!=success_cycle[good_id]+1)
         $fatal(1,"recovered report id=%0d seq=%0d CRC=%h/%h counters=%0d/%0d/%0d",latest.frame_id,
           latest.diagnostic_seq,latest.raw_crc,latest.selected_crc,
           latest.accepted_frames,latest.completed_frames,latest.invalid_frames);
       last_seq=latest.diagnostic_seq;reports=reports+1;
     end
   end
 end
 function automatic frame_config_t configuration(input integer f);
   frame_config_t c;
   begin c='0;c.epsilon=1024;c.view_mode=(f<4)?f:3;
     c.threshold=(f==2)?2:(f==3 || f>=4)?4:0;
     c.gain=(f==2)?256:(f==3 || f>=4)?428:0;
     c.cfg_id=100+f;c.profile_id=1;c.source_kind=1;c.pattern_id=0;configuration=c;end
 endfunction
 function automatic [63:0] token_for(input integer f,input integer i);
   reg [7:0] p;begin p=i%W+i/W+f;
     token_for=pack_pixel(p,i%W,i/W,i==0,i%W==W-1,i==INPUTS-1,f);end
 endfunction
 task tick(input bit v,input [63:0] token,input bit ev,input integer f,input bit ok,input [3:0] reason);
   begin @(negedge clk);source_valid=v;source_token=token;source_end_valid=ev;
     source_end={f[31:0],ok,reason};@(posedge clk);#1;end
 endtask
 task idle(input integer count);
   integer n;begin for(n=0;n<count;n=n+1)tick(0,0,0,0,1,0);end
 endtask
 task send_frame(input integer f,input integer corruption,input integer ending);
   integer i;reg [63:0] token;reg injected;
   begin
     shadow_config=configuration(f);injected=0;
     for(i=0;i<INPUTS;i=i+1)begin
       token=token_for(f,i);
       if((corruption==1 && i==20) || (corruption==2 && bad_prefix!=0 && !injected))begin
         token[17:8]=token[17:8]+1'b1;injected=1;
       end
       tick(1,token,ending==1 && i==INPUTS-1,f,1,0);
       if(i==2*W)begin
         shadow_config=configuration(500);shadow_config.epsilon=16;
       end
       if(i%11==7)idle(i%3+1);
     end
     if(corruption!=0 && !injected)$fatal(1,"protocol injection missed active output");
   end
 endtask
 task wait_reports(input integer target);
   integer budget;begin budget=0;
     while(reports<target && budget<INPUTS+L+40)begin idle(1);budget=budget+1;end
     if(reports!=target)$fatal(1,"recovery report timeout target=%0d got=%0d reason=%0d",target,reports,last_reason);
   end
 endtask
 task same_edge_ok(input integer f);
   integer budget;reg sent;
   begin
     budget=0;sent=0;
     while(!sent && budget<L+INPUTS+20)begin
       @(negedge clk);source_valid=0;source_token=0;source_end_valid=0;
       if(eof && id==f)begin source_end_valid=1;source_end={f[31:0],1'b1,4'd0};sent=1;end
       @(posedge clk);#1;budget=budget+1;
     end
     if(!sent)$fatal(1,"same-edge source OK not sent");
   end
 endtask
 integer i,budget;
 initial begin
   source_end='0;shadow_config=configuration(0);
   if(!$value$plusargs("VECTORS=%s",vectors))$fatal(1,"recovery vectors missing");
   for(i=0;i<4;i=i+1)begin
     filename=$sformatf("%s/expected_p0_f%0d.hex",vectors,i);
     $readmemh(filename,expected,i*N,(i+1)*N-1);
   end
   filename={vectors,"/raw_crc_p0.hex"};$readmemh(filename,raw_crc);
   filename={vectors,"/selected_crc_p0.hex"};$readmemh(filename,selected_crc);
   repeat(3)@(negedge clk);rst=0;
   // Reset wins while an accepted frame has tokens in RAM/core pipelines.
   shadow_config=configuration(200);for(i=0;i<20;i=i+1)tick(1,token_for(200,i),0,0,1,0);
   if(accepted!=1)$fatal(1,"reset episode never accepted");
   @(negedge clk);rst=1;source_valid=1;source_token=token_for(201,0);
   source_end_valid=1;source_end={32'd200,1'b0,4'd4};@(posedge clk);#2;
   if(accepted || completed || bad || valid || latest_valid || core_abort)$fatal(1,"reset priority/state leak");
   @(negedge clk);source_valid=0;source_token=0;source_end_valid=0;rst=0;
   send_frame(100,1,1);idle(L+8);
   if(bad!=1 || invalid_events!=1 || completed || latest_valid)$fatal(1,"warmup protocol error handling");
   send_frame(0,0,1);wait_reports(1);last_good=latest;
   send_frame(101,2,1);idle(L+8);
   if(bad!=2 || invalid_events!=2 || bad_prefix==0 || latest!==last_good)
     $fatal(1,"output-prefix invalidation polluted last_good");
   send_frame(1,0,0);same_edge_ok(1);wait_reports(2);last_good=latest;
   send_frame(102,0,0);budget=0;
   while(!bad_full_eof && budget<L+INPUTS+20)begin idle(1);budget=budget+1;end
   if(!bad_full_eof || bad_full_count!=N || latest!==last_good || completed!=2)
     $fatal(1,"source status was not required after full output");
   idle(4);tick(0,0,1,102,0,4);idle(L+8);
   if(bad!=3 || invalid_events!=3 || latest!==last_good)$fatal(1,"late source ERROR committed CRC");
   send_frame(2,0,0);budget=0;
   while(output_index[2]!=N && budget<L+INPUTS+20)begin idle(1);budget=budget+1;end
   if(output_index[2]!=N)$fatal(1,"late OK frame lacked output EOF");
   idle(6);tick(0,0,1,2,1,0);wait_reports(3);
   send_frame(3,0,1);wait_reports(4);idle(L+12);
   if(accepted!=7 || completed!=4 || bad!=3 || seen!=7 || dropped || invalid_events!=3 ||
      good_frames!=4 || good_outputs!=4*N || overwrites!=3 || abort_edges<3 ||
      accepted!=completed+bad || seen!=accepted+dropped)
     $fatal(1,"recovery final identities seen=%0d accepted=%0d completed=%0d invalid=%0d dropped=%0d",seen,accepted,completed,bad,dropped);
   if(!(source_ok_cycle[0]<output_eof_cycle[0] && source_ok_cycle[1]==output_eof_cycle[1] &&
        source_ok_cycle[2]>output_eof_cycle[2] && source_ok_cycle[3]<output_eof_cycle[3]))
     $fatal(1,"source OK early/simultaneous/late coverage");
   $display("PASS tb_runtime_recovery W=%0d H=%0d align=%0d good_frames=%0d invalid_frames=%0d pixels=%0d bad_prefix=%0d bad_full=%0d abort_edges=%0d cycles=%0d",W,H,EXTRA_ALIGN,
      good_frames,bad,good_outputs,bad_prefix,bad_full_count,abort_edges,cycle);$finish;
 end
 initial begin repeat(20*INPUTS+20*L+2000)@(posedge clk);$fatal(1,"actual-core recovery timeout");end
endmodule
