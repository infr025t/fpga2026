`timescale 1ns/1ps
module tb_runtime_core #(parameter integer W=16,H=16,PATTERN_ID=0,EXTRA_ALIGN=0,CLAIM_MODE=0);
  import video_runtime_pkg::*;
  reg clk=0;always #5 clk=~clk;
  reg rst=1;
  wire source_valid,end_valid;wire [63:0] token;source_end_t source_end;
  wire [31:0] source_id=token[61:30];
  source_pattern #(W,H,PATTERN_ID,core_latency_pkg::L_CORE+EXTRA_ALIGN) source(
    .clk(clk),.rst(rst),.enable(source_id<4),.token_valid(source_valid),.token(token),
    .end_valid(end_valid),.end_status(source_end));
  frame_config_t shadow;
  always @*begin
    shadow='0;shadow.epsilon=1024;shadow.view_mode=source_id[1:0];
    shadow.threshold=(source_id[1:0]==2)?2:(source_id[1:0]==3)?4:0;
    shadow.gain=(source_id[1:0]==2)?256:(source_id[1:0]==3)?428:0;
    shadow.profile_id=1;shadow.cfg_id=100+source_id;
    shadow.source_kind=1;shadow.pattern_id=PATTERN_ID;
  end
  wire [7:0] pixel,raw,base;wire valid,sof,eol,eof,latest_valid,claimed_valid;
  wire [9:0] x;wire [8:0] y;wire [31:0] id,seen,accepted,completed,invalid,dropped,overflows,cfg_errors,overwrites;
  wire [10:0] highwater;core_report_t latest,claimed;
  integer cycle=0;
  wire claim=CLAIM_MODE==1 || (CLAIM_MODE==2 && cycle%37==0);
  video_runtime #(W,H,EXTRA_ALIGN) dut(
    .clk(clk),.rst(rst),.source_valid(source_valid),.source_token(token),.source_end_valid(end_valid),
    .source_end(source_end),.shadow_config(shadow),.stop_request(1'b0),.claim(claim),
    .latest_valid(latest_valid),.latest(latest),.claimed_valid(claimed_valid),.claimed_report(claimed),
    .out_pixel(pixel),.out_raw(raw),.out_base(base),.out_valid(valid),.out_x(x),.out_y(y),
    .out_sof(sof),.out_eol(eol),.out_eof(eof),.out_frame_id(id),
    .seen_frames(seen),.accepted_frames(accepted),.completed_frames(completed),.invalid_frames(invalid),
    .dropped_source(dropped),.overflow_count(overflows),.cfg_error(cfg_errors),.overwrite_count(overwrites),
    .fifo_highwater(highwater));
  localparam integer N=(W-8)*(H-8),L=core_latency_pkg::L_CORE+EXTRA_ALIGN;
  reg [23:0] expected[0:N-1];reg [31:0] raw_crc[0:3],selected_crc[0:3];
  integer pixels=0,index=0,frames=0,reports=0,input_eof_cycle=0;
  integer last_seq=0;string vectors,filename;
  always @(posedge clk)begin
    cycle=cycle+1;
    if(!rst && dut.iv && dut.eof)input_eof_cycle=cycle;
    #1;
    if(!rst)begin
      if(invalid || dropped || overflows || cfg_errors || dut.core_abort)
        $fatal(1,"runtime unexpected fault cycle=%0d invalid=%0d dropped=%0d reason=%0d",cycle,invalid,dropped,dut.last_reason);
      if(valid)begin
        if(sof)begin
          if(index!=0 || id!=frames)$fatal(1,"runtime output SOF/id");
          filename=$sformatf("%s/expected_p%0d_f%0d.hex",vectors,PATTERN_ID,id);$readmemh(filename,expected);
        end
        if(x!=4+index%(W-8) || y!=4+index/(W-8) || id!=frames ||
           sof!==(index==0) || eol!==(index%(W-8)==W-9) || eof!==(index==N-1))
          $fatal(1,"runtime raster index=%0d xy=%0d,%0d",index,x,y);
        if({raw,base,pixel}!==expected[index])
          $fatal(1,"runtime pixel pattern=%0d frame=%0d index=%0d got=%h want=%h",PATTERN_ID,id,index,{raw,base,pixel},expected[index]);
        pixels=pixels+1;
        if(eof)begin
          if(cycle-input_eof_cycle!=L)$fatal(1,"runtime numeric latency");
          frames=frames+1;index=0;
        end else index=index+1;
      end
      if(latest_valid && latest.diagnostic_seq!=last_seq)begin
        if(latest.diagnostic_seq!=reports+1 || latest.frame_id!=reports || latest.pixel_count!=N ||
           latest.raw_crc!==raw_crc[reports] || latest.selected_crc!==selected_crc[reports] ||
           latest.frame_config.view_mode!=reports || latest.frame_config.cfg_id!=100+reports ||
           latest.frame_config.pattern_id!=PATTERN_ID || latest.completed_frames!=reports+1 || latest.invalid_frames!=0)
          $fatal(1,"runtime report frame=%0d mode=%0d CRC=%h/%h counters=%0d",latest.frame_id,latest.frame_config.view_mode,latest.raw_crc,latest.selected_crc,latest.completed_frames);
        last_seq=latest.diagnostic_seq;reports=reports+1;
      end
    end
  end
  initial begin
    if(!$value$plusargs("VECTORS=%s",vectors))$fatal(1,"runtime vectors missing");
    filename=$sformatf("%s/raw_crc_p%0d.hex",vectors,PATTERN_ID);$readmemh(filename,raw_crc);
    filename=$sformatf("%s/selected_crc_p%0d.hex",vectors,PATTERN_ID);$readmemh(filename,selected_crc);
    repeat(3)@(negedge clk);rst=0;
    wait(reports==4);repeat(8)@(negedge clk);
    if(frames!=4 || pixels!=4*N || seen!=4 || accepted!=4 || completed!=4 || highwater>8)
      $fatal(1,"runtime final counts %0d/%0d/%0d highwater=%0d",seen,accepted,completed,highwater);
    if(CLAIM_MODE==0 && overwrites!=3)$fatal(1,"unclaimed mailbox overwrite count");
    if(CLAIM_MODE==1 && overwrites!=0)$fatal(1,"always-claim mailbox overwrite count");
    $display("PASS tb_runtime_core W=%0d H=%0d pattern=%0d align=%0d claim=%0d frames=%0d pixels=%0d highwater=%0d",W,H,PATTERN_ID,EXTRA_ALIGN,CLAIM_MODE,frames,pixels,highwater);$finish;
  end
  initial begin repeat(4*W*H+4*L+10000)@(posedge clk);$fatal(1,"runtime integration timeout");end
endmodule
