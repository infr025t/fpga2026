`timescale 1ns/1ps
module tb_core_crc;
 import video_runtime_pkg::*;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,abort=0,out_valid=0,out_sof=0,out_eol=0,out_eof=0;
 reg [7:0] out_pixel=0,out_raw=0;
 reg [9:0] out_x=0;reg [8:0] out_y=0;reg [31:0] out_frame_id=0;
 reg frame_start_valid=0,frame_success_valid=0,frame_invalid_valid=0;
 reg [31:0] frame_start_id=0,frame_success_id=0,frame_invalid_id=0;
 reg [3:0] frame_invalid_reason=0;
 frame_config_t frame_start_config;
 reg [31:0] completed_frames=0,invalid_frames=0,accepted_frames=0;
 wire core_done_valid,core_done_ok,latest_valid,claimed_valid;
 wire [31:0] core_done_frame_id,overwrite_count;
 core_report_t latest,claimed_report;
 reg claim=0;
 core_crc_monitor #(16,16) dut(.*);
 reg [31:0] crc_state=32'hffffffff;reg [7:0] crc_data=0;wire [31:0] crc_next;
 crc32_byte crc_byte(.state(crc_state),.data(crc_data),.next_state(crc_next));
 integer i,j,cycle=0,pubs=0;reg [31:0] saved_overwrite,saved_accepted;core_report_t saved_claim,saved_report;
 always @(posedge clk)begin
   cycle<=cycle+1;
   if(rst)begin completed_frames<=0;invalid_frames<=0;accepted_frames<=0;end
   else begin
     if(frame_start_valid)accepted_frames<=accepted_frames+1'b1;
     if(frame_success_valid)completed_frames<=completed_frames+1'b1;
     if(frame_invalid_valid)invalid_frames<=invalid_frames+1'b1;
   end
 end
 task clear_inputs;
 begin
   abort=0;out_valid=0;out_sof=0;out_eol=0;out_eof=0;claim=0;
   frame_start_valid=0;frame_success_valid=0;frame_invalid_valid=0;
 end endtask
 task tick;
 begin @(posedge clk);#1;end endtask
 task idle(input integer do_claim);
 begin @(negedge clk);clear_inputs();claim=do_claim;tick();end endtask
 task configuration(input integer id);
 begin
   frame_start_config='0;frame_start_config.epsilon=1024;
   frame_start_config.threshold=4;frame_start_config.gain=428;
   frame_start_config.view_mode=3;frame_start_config.cfg_id=id;
   frame_start_config.profile_id=1;frame_start_config.pattern_id=id;
   frame_start_config.preview_enable=1;
 end endtask
 task start_frame(input integer id);
 begin
   @(negedge clk);clear_inputs();frame_start_valid=1;frame_start_id=id;
   configuration(id);tick();
 end endtask
 // mutation: 1 first RAW byte, 2 last RAW byte, 3 RAW mode,
 // 4 duplicate SOF, 5 wrong coordinate, 6 abort at EOF,
 // 7 old EOF+success and next accepted input SOF on the same edge.
 task pixel(input integer id,input integer index,input integer success_kind,input integer mutation);
 begin
   @(negedge clk);clear_inputs();out_valid=1;out_frame_id=id;
   out_x=4+index%8;out_y=4+index/8;
   out_raw=(index*3+7)&255;out_pixel=(out_raw+13)&255;
   if(mutation==1 && index==0)out_raw=out_raw^1;
   if(mutation==2 && index==63)out_raw=out_raw^1;
   if(mutation==3)out_pixel=out_raw;
   out_sof=(index==0 || (mutation==4 && index==3));
   out_eol=(index%8==7);out_eof=(index==63);
   if(mutation==5 && index==7)out_x=4;
   if((success_kind==1 && index==63) || (success_kind==2 && index==0))begin
     frame_success_valid=1;frame_success_id=id;
   end
   // Unrelated bus changes must not mutate the accepted descriptor.
   configuration(16'hdead);
   if(mutation==6 && index==63)begin abort=1;frame_success_valid=0;end
   if(mutation==7 && index==63)begin
     frame_start_valid=1;frame_start_id=id+1;configuration(id+1);
   end
   #1;
   if(out_eof)begin
     if(mutation==6)begin if(core_done_valid!==0)$fatal(1,"abort must mask core_done");end
     else begin
       if(core_done_valid!==1 || core_done_frame_id!==id)$fatal(1,"EOF completion preview");
       if(core_done_ok!==!(mutation==4 || mutation==5))$fatal(1,"EOF malformed classification");
     end
   end
   tick();
 end endtask
 task frame(input integer id,input integer success_kind,input integer mutation);
 begin
   start_frame(id);
   for(i=0;i<64;i=i+1)begin
     pixel(id,i,success_kind,mutation);
     if(i%7==3)idle(0);
   end
 end endtask
 task expect_report(input integer id,input reg[31:0] raw_crc,input reg[31:0] selected_crc);
 begin
   if(!latest_valid || latest.frame_id!==id || latest.frame_config.cfg_id!==id[15:0] ||
      latest.pixel_count!==64 || latest.raw_crc!==raw_crc || latest.selected_crc!==selected_crc ||
      latest.completed_frames!==completed_frames || latest.invalid_frames!==invalid_frames ||
      latest.accepted_frames!==accepted_frames || latest.report_overwrite_count!==overwrite_count)
     $fatal(1,"report mismatch id=%0d latest=%h",id,latest);
   pubs=pubs+1;
 end endtask
 task source_success(input integer id);
 begin
   @(negedge clk);clear_inputs();frame_success_valid=1;frame_success_id=id;tick();
 end endtask
 initial begin
   frame_start_config='0;
   // Independent constants generated with Python zlib.crc32. Empty input is 0.
   if((crc_state^32'hffffffff)!==0)$fatal(1,"empty CRC");
   for(j=0;j<9;j=j+1)begin crc_data=8'h31+j;#1;crc_state=crc_next;#1;end
   if((crc_state^32'hffffffff)!==32'hcbf43926)$fatal(1,"CRC standard vector");
   crc_state=32'hffffffff;crc_data=0;#1;
   if((crc_next^32'hffffffff)!==32'hd202ef8d)$fatal(1,"single zero CRC");
   crc_data=255;#1;if((crc_next^32'hffffffff)!==32'hff000000)$fatal(1,"single ff CRC");
   tick();@(negedge clk);rst=0;clear_inputs();tick();
   if(latest_valid || claimed_valid)$fatal(1,"reset report validity");
   frame(1,1,0);
   if(latest_valid)$fatal(1,"report published on completion edge");
   idle(0);expect_report(1,32'h1d13a5cf,32'h49b4f261);
   if(latest.diagnostic_seq!==1 || overwrite_count!==0)$fatal(1,"initial report bookkeeping");
   frame(2,2,0);
   if(latest.frame_id!==1)$fatal(1,"early source success published before EOF");
   idle(1);expect_report(2,32'h1d13a5cf,32'h49b4f261);
   if(!claimed_valid || claimed_report.frame_id!==1 || overwrite_count!==0)
     $fatal(1,"claim/publication ordering or overwrite");
   saved_claim=claimed_report;
   frame(3,0,0);repeat(3)idle(0);
   if(latest.frame_id!==2)$fatal(1,"published without source success");
   source_success(3);if(latest.frame_id!==2)$fatal(1,"late source published too early");
   idle(0);expect_report(3,32'h1d13a5cf,32'h49b4f261);
   if(overwrite_count!==1 || claimed_report!==saved_claim)$fatal(1,"immutable claim or overwrite count");
   idle(1);saved_claim=claimed_report;
   for(j=4;j<=103;j=j+1)begin
     frame(j,1,0);idle(0);expect_report(j,32'h1d13a5cf,32'h49b4f261);
     if(claimed_report!==saved_claim)$fatal(1,"claimed report mutated during 100 publications");
   end
   if(overwrite_count!==100 || latest.diagnostic_seq!==103)$fatal(1,"latest overwrite/sequence");
   frame(104,1,1);idle(0);expect_report(104,32'h9226885a,32'h49b4f261);
   frame(105,1,2);idle(0);expect_report(105,32'h6a149559,32'h49b4f261);
   frame(106,1,3);idle(0);expect_report(106,32'h1d13a5cf,32'h1d13a5cf);
   frame(107,1,7);idle(0);expect_report(107,32'h1d13a5cf,32'h49b4f261);
   for(i=0;i<64;i=i+1)pixel(108,i,1,0);
   idle(0);expect_report(108,32'h1d13a5cf,32'h49b4f261);
   // Bad output is never a successful report, even if success is asserted.
   frame(109,1,4);idle(0);if(latest.frame_id!==108)$fatal(1,"duplicate SOF report");
   frame(110,1,5);idle(0);if(latest.frame_id!==108)$fatal(1,"wrong coordinates report");
   frame(111,1,6);idle(0);if(latest.frame_id!==108)$fatal(1,"abort at EOF report");
   frame(112,0,0);
   @(negedge clk);clear_inputs();abort=1;tick();
   source_success(112);idle(0);if(latest.frame_id!==108)$fatal(1,"aborted pending report");
   start_frame(113);
   for(i=0;i<62;i=i+1)pixel(113,i,0,0);
   @(negedge clk);clear_inputs();out_valid=1;out_eof=1;out_eol=1;
   out_x=11;out_y=11;out_frame_id=113;#1;
   if(!core_done_valid || core_done_ok)$fatal(1,"early EOF count guard");
   tick();idle(0);if(latest.frame_id!==108)$fatal(1,"early EOF report");
   // Reset wins over output EOF and source success, then a clean frame recovers.
   start_frame(114);for(i=0;i<63;i=i+1)pixel(114,i,0,0);
   @(negedge clk);clear_inputs();rst=1;out_valid=1;out_eof=1;out_eol=1;out_frame_id=114;tick();
   if(latest_valid || claimed_valid || core_done_valid)$fatal(1,"reset at EOF");
   @(negedge clk);rst=0;clear_inputs();tick();
   frame(115,1,0);idle(0);expect_report(115,32'h1d13a5cf,32'h49b4f261);
   if(latest.diagnostic_seq!==1 || overwrite_count!==0)$fatal(1,"reset sequence");
   // Publication snapshots pre-edge counters if a new frame is accepted there.
   frame(116,1,0);saved_accepted=accepted_frames;
   @(negedge clk);clear_inputs();frame_start_valid=1;frame_start_id=117;configuration(117);tick();
   if(latest.frame_id!==116 || latest.accepted_frames!==saved_accepted ||
      accepted_frames!==saved_accepted+1 || latest.frame_config.cfg_id!==116)
     $fatal(1,"publication/acceptance counter snapshot");
   pubs=pubs+1;saved_report=latest;
   for(i=0;i<64;i=i+1)pixel(117,i,0,0);
   repeat(2)idle(0);
   if(latest!==saved_report)$fatal(1,"published report mutated with live counters");
   // An explicit invalidation beats a simultaneous source-success/EOF commit.
   source_success(117);
   @(negedge clk);clear_inputs();frame_invalid_valid=1;frame_invalid_id=117;frame_invalid_reason=4;tick();
   idle(0);if(latest.frame_id!==116)$fatal(1,"invalid pending publication");
   start_frame(118);
   for(i=0;i<63;i=i+1)pixel(118,i,0,0);
   @(negedge clk);clear_inputs();out_valid=1;out_frame_id=118;
   out_raw=(63*3+7)&255;out_pixel=(out_raw+13)&255;
   out_x=11;out_y=11;out_eol=1;out_eof=1;
   frame_success_valid=1;frame_success_id=118;
   frame_invalid_valid=1;frame_invalid_id=118;frame_invalid_reason=3;tick();
   idle(0);if(latest.frame_id!==116)$fatal(1,"invalid EOF publication");
   // A mismatched source-success cannot authorize a different pending frame.
   frame(119,0,0);source_success(120);idle(0);
   if(latest.frame_id!==116)$fatal(1,"mismatched success publication");
   source_success(119);idle(0);expect_report(119,32'h1d13a5cf,32'h49b4f261);
   // Seed public bookkeeping state to exercise unreachable-in-short-test limits.
   force dut.overwrite_count=32'hfffffffe;force dut.diagnostic_seq=32'hffffffff;
   idle(0);release dut.overwrite_count;release dut.diagnostic_seq;
   frame(32'hffffffff,1,0);idle(0);
   expect_report(32'hffffffff,32'h1d13a5cf,32'h49b4f261);
   if(overwrite_count!==32'hffffffff || latest.diagnostic_seq!==0)
     $fatal(1,"saturating overwrite/modulo diagnostic sequence");
   frame(0,1,0);idle(0);expect_report(0,32'h1d13a5cf,32'h49b4f261);
   if(overwrite_count!==32'hffffffff || latest.diagnostic_seq!==1)
     $fatal(1,"frame wrap or saturation hold");
   $display("PASS tb_core_crc publications=%0d cycles=%0d standard_vector/first/last/RAW/gaps/config/late/early/atomic_claim/abort/reset/invalid/snapshots/saturation/wrap",pubs,cycle);
   $finish;
 end
 initial begin repeat(20000)@(posedge clk);$fatal(1,"CRC test timeout");end
endmodule
