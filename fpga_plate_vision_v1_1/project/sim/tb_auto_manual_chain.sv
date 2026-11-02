`timescale 1ns/1ps
// 实际模式复用层：人工协议黄金比对及 AUTO/MANUAL/DIAG 中断恢复。
module tb_auto_manual_chain;
 reg clk=0;always #5 clk=~clk;reg rst=1,rxd=1;wire txd;
 wire ss,sb,sdone,swe;wire[7:0]serr,sx,sy,sw,sh,srd;wire[31:0]scycles;
 wire[5:0]sindex;wire[6:0]scount;wire[14:0]sra;
 wire fw,ns,cs,iw,wr,nb,nd,ne,pw,cb,cd,sv,fv;
 wire[14:0]fa;wire[7:0]fd,id,pd;wire[9:0]ia,pa;wire[5:0]si;wire signed[31:0]sd;
 wire[7:0]bx,by,bw,bh,rx0,ry0,rx1,ry1;wire[1:0]flags;
 wire[31:0]nc,cc,accepted,crc_errors,rx_errors,frame_id;
 reg manual_mode=0,diagnostic_mode=0,camera_enable=0,monitor_uart=0;
 reg source_start=0,source_valid=0,source_done=0,source_error=0;
 reg[7:0]source_pixel=0;reg[9:0]source_x=0;reg[8:0]source_y=0;
 wire[127:0]status;
 plate_recognition_subsystem #(.AUTO_LOCATE(1),.SKIP_CHINESE(1),.SPLIT_TOUCHING(1)) dut(.clk(clk),.rst(rst),.recognition_enable(1'b1),.white_characters(1'b0),.manual_mode(manual_mode),.diagnostic_mode(diagnostic_mode),
  .uart_rxd(rxd),.uart_txd(txd),.source_start(source_start),.source_valid(source_valid),.source_done(source_done),.source_error(source_error),
  .source_pixel(source_pixel),.source_x(source_x),.source_y(source_y),.status(status));
 // 保留原人工链测试的所有数值检查，仅将监视信号绑定实际子系统。
 assign ss=dut.m_ss;assign sb=dut.sb;assign sdone=dut.sd;assign swe=dut.sbw;
 assign serr=dut.se;assign sx=dut.sbx;assign sy=dut.sby;assign sw=dut.sbww;assign sh=dut.sbh;
 assign scycles=dut.sc;assign sindex=dut.sbi;assign scount=dut.sbc;assign sra=dut.sra;assign srd=dut.srd;
 assign fw=dut.m_fw;assign fa=dut.m_fa;assign fd=dut.m_fd;assign wr=dut.m_reset;
 assign ns=dut.m_ns;assign nb=dut.nb;assign nd=dut.nd;assign ne=dut.ne;assign nc=dut.nc;
 assign pw=dut.npw;assign pa=dut.npa;assign pd=dut.npd;
 assign cs=dut.m_cs;assign cb=dut.cb;assign cd=dut.cd;assign cc=dut.cc;
 assign iw=dut.m_cwe;assign ia=dut.m_ca;assign id=dut.m_cd;
 assign sv=dut.csv;assign si=dut.csi;assign sd=dut.csd;
 assign bx=dut.bx;assign by=dut.by;assign bw=dut.bw;assign bh=dut.bh;
 assign rx0=dut.rx0;assign ry0=dut.ry0;assign rx1=dut.rx1;assign ry1=dut.ry1;assign flags=dut.fl;
 assign accepted=dut.m_accepted;assign crc_errors=dut.m_crc;assign rx_errors=dut.m_rx;
 assign fv=dut.manual_transport.frame_valid;assign frame_id=dut.manual_transport.frame_id;
 integer source_offset=0,auto_sample_writes=0,manual_sample_writes=0,ignored_camera_frames=0;
 always @(negedge clk)begin
  if(rst||!camera_enable)begin source_start=0;source_valid=0;source_done=0;source_offset=0;end
  else begin
   source_start=(source_offset==0);source_valid=1;source_done=(source_offset==307199);
   source_x=source_offset%640;source_y=source_offset/640;source_pixel=8'ha5;
   if(source_offset==307199)source_offset=0;else source_offset=source_offset+1;
  end
 end
 always @(posedge clk)if(!rst)begin
  if(dut.a_fw)auto_sample_writes=auto_sample_writes+1;
  if(manual_mode&&!dut.mode_changed)begin
   if(dut.auto_busy||dut.a_fw||dut.a_ss||dut.a_ns||dut.a_cs)$fatal(1,"AUTO must remain reset in MANUAL");
   if(source_start)ignored_camera_frames=ignored_camera_frames+1;
   if(dut.normalize_character.frame_we)begin
    if(!fw||dut.normalize_character.frame_addr!==fa||dut.normalize_character.frame_data!==fd)$fatal(1,"manual RAM ownership mux");
    manual_sample_writes=manual_sample_writes+1;
   end
  end
  if(diagnostic_mode)begin
   if(dut.normalize_character.frame_we||dut.recognizer.in_we)$fatal(1,"DIAG must not write shared recognition RAM");
   if(!dut.work_rst)$fatal(1,"DIAG must hold workers reset");
  end
 end
 reg[7:0]frames[0:38423],segments[0:41],characters[0:24],counts[0:1],pixels[0:1535],reply[0:935],sampled;
 reg[31:0]scores[0:71],boxes[0:127];integer rx_count=0,replies=0,expected_size=0,active_case=0,writes=0;
 integer norm_starts=0,core_starts=0,completions=0,observed_nc=0,observed_cc=0,saved_nc=0,saved_cc=0;
 integer seg_starts=0,seg_outputs=0,seg_completions=0,observed_sc=0,saved_sc=0;
 reg[35:0]score_mask=0;
 function automatic[31:0]crc_byte(input[31:0]c,input[7:0]b);
  reg[31:0]v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 always @(posedge clk)if(!rst)begin
  if((sb&&nb)||(sb&&cb)||(nb&&cb))$fatal(1,"workers must not overlap on shared RAM");
  if(ss)begin seg_starts=seg_starts+1;seg_outputs=0;observed_sc=0;end
  if(sb)begin observed_sc=observed_sc+1;if(sra>=19200)$fatal(1,"segment frame read out of bounds");end
  if(swe)begin
   if(sindex!==seg_outputs[5:0] || {sh,sw,sy,sx}!==boxes[active_case*64+seg_outputs])
    $fatal(1,"segment golden mismatch case=%0d index=%0d got=%h expected=%h",active_case,seg_outputs,{sh,sw,sy,sx},boxes[active_case*64+seg_outputs]);
   seg_outputs=seg_outputs+1;
  end
  if(sdone)begin
   if(serr||swe||scount!==counts[active_case]||seg_outputs!=counts[active_case]||scycles!==observed_sc)
    $fatal(1,"segment done/error/count/cycles case=%0d error=%0d boxes=%0d count=%0d cycles=%0d observed=%0d",active_case,serr,seg_outputs,scount,scycles,observed_sc);
   saved_sc=observed_sc;seg_completions=seg_completions+1;
  end
  if(wr)$fatal(1,"unexpected worker reset");
  if(ns)begin norm_starts=norm_starts+1;writes=0;observed_nc=0;end
  if(nb)observed_nc=observed_nc+1;
  if(nd)begin
   if(ne||writes!=768||nc!==observed_nc)$fatal(1,"normalizer done/pixel/cycle alignment writes=%0d cycles=%0d observed=%0d",writes,nc,observed_nc);
   saved_nc=observed_nc;
  end
  if(iw)begin
   if(cb||ia!==writes[9:0]||id!==pixels[active_case*768+writes])$fatal(1,"normalizer golden mismatch case=%0d addr=%0d",active_case,writes);
   writes=writes+1;
  end
  if(cs)begin if(writes!=768||nb)$fatal(1,"CNN premature launch");core_starts=core_starts+1;observed_cc=0;score_mask=0;end
  if(cb)observed_cc=observed_cc+1;
  if(sv)begin
   if(si>=36||sd!==scores[active_case*36+si])$fatal(1,"CNN golden mismatch case=%0d score=%0d got=%h expected=%h",active_case,si,sd,scores[active_case*36+si]);
   score_mask[si]=1;
  end
  if(cd)begin
   if(cc!==observed_cc||!(&score_mask))$fatal(1,"CNN done/cycles/mask mismatch");
   completions=completions+1;saved_cc=observed_cc;
  end
 end
 initial forever begin
  @(negedge txd);if(manual_mode&&monitor_uart)begin #(83.333333*1.5);
  for(integer k=0;k<8;k=k+1)begin sampled[k]=txd;#83.333333;end
  if(txd!==1)$fatal(1,"TX stop bit");reply[rx_count]=sampled;rx_count=rx_count+1;
  if(rx_count==3)expected_size=(reply[1]=="F")?16:((reply[1]=="S")?280:936);
  if(rx_count==expected_size && expected_size!=0)begin replies=replies+1;rx_count=0;expected_size=0;end
  end
 end
 task automatic send_byte(input[7:0]b);
  begin rxd=0;#83.333333;for(integer k=0;k<8;k=k+1)begin rxd=b[k];#83.333333;end rxd=1;#83.333333;end
 endtask
 task automatic check_reply(input integer seq,input bit ack);
  reg[31:0]c,got;integer size;begin
   size=ack?16:936;
   if(reply[0]!=="N"||reply[1]!==(ack?"F":"R")||reply[2]!==(ack?"A":"S")||reply[3]!=="1")$fatal(1,"reply magic");
   got={reply[7],reply[6],reply[5],reply[4]};if(got!==seq)$fatal(1,"reply seq");
   got={reply[11],reply[10],reply[9],reply[8]};if(got!==0)$fatal(1,"reply status=%0d",got);
   if(!ack)begin
    got={reply[15],reply[14],reply[13],reply[12]};if(got!==saved_nc)$fatal(1,"norm reported cycles");
    got={reply[19],reply[18],reply[17],reply[16]};if(got!==saved_cc)$fatal(1,"CNN reported cycles");
    for(integer k=0;k<768;k=k+1)if(reply[20+k]!==pixels[active_case*768+k])$fatal(1,"reply pixel %0d",k);
    for(integer k=0;k<36;k=k+1)begin
     got={reply[791+4*k],reply[790+4*k],reply[789+4*k],reply[788+4*k]};if(got!==scores[active_case*36+k])$fatal(1,"reply score %0d",k);
    end
   end
   c=32'hffffffff;for(integer k=0;k<size-4;k=k+1)c=crc_byte(c,reply[k]);
   got={reply[size-1],reply[size-2],reply[size-3],reply[size-4]};if(got!==~c)$fatal(1,"reply CRC");
  end endtask
 task automatic check_segment_reply(input integer seq);
  reg[31:0]c,got;begin
   if({reply[0],reply[1],reply[2],reply[3]}!=="NSR1")$fatal(1,"NSR1 magic");
   got={reply[7],reply[6],reply[5],reply[4]};if(got!==seq)$fatal(1,"NSR1 seq");
   got={reply[11],reply[10],reply[9],reply[8]};if(got!==0)$fatal(1,"NSR1 status=%0d",got);
   got={reply[15],reply[14],reply[13],reply[12]};if(got!==saved_sc)$fatal(1,"NSR1 cycles");
   got={reply[19],reply[18],reply[17],reply[16]};if(got!==counts[active_case])$fatal(1,"NSR1 count");
   for(integer k=0;k<64;k=k+1)begin
    got={reply[23+4*k],reply[22+4*k],reply[21+4*k],reply[20+4*k]};
    if(got!==boxes[active_case*64+k])$fatal(1,"NSR1 golden box/zero-fill case=%0d slot=%0d",active_case,k);
   end
   c=32'hffffffff;for(integer k=0;k<276;k=k+1)c=crc_byte(c,reply[k]);
   got={reply[279],reply[278],reply[277],reply[276]};if(got!==~c)$fatal(1,"NSR1 CRC");
  end
 endtask
 task automatic character_from_fpga_reply(input integer seq,input integer fid);
  reg[31:0]c;begin
   characters[0]="N";characters[1]="C";characters[2]="H";characters[3]="1";
   for(integer k=0;k<4;k=k+1)begin
    characters[4+k]=seq>>(8*k);characters[8+k]=fid>>(8*k);
    characters[12+k]=reply[20+k]; // The request is driven by received FPGA boxes.
    characters[16+k]=segments[active_case*21+12+k];
   end
   characters[20]=segments[active_case*21+16];
   c=32'hffffffff;for(integer k=0;k<21;k=k+1)c=crc_byte(c,characters[k]);c=~c;
   for(integer k=0;k<4;k=k+1)characters[21+k]=c>>(8*k);
  end
 endtask
 initial begin
  $readmemh("frames.hex",frames);$readmemh("segments.hex",segments);$readmemh("pixels.hex",pixels);$readmemh("scores.hex",scores);
  $readmemh("boxes.hex",boxes);$readmemh("counts.hex",counts);
  #100;@(negedge clk);rst=0;camera_enable=1;
  // AUTO 半帧持有缓存；切到 MANUAL 后清除所有权，剩余视频继续到达。
  repeat(256)@(negedge clk);
  if(!dut.auto_busy||auto_sample_writes==0)$fatal(1,"AUTO setup did not acquire partial frame");
  #1;manual_mode=1;repeat(5)@(negedge clk);
  if(dut.auto_busy||fv||dut.sb||dut.nb||dut.cb)$fatal(1,"AUTO to MANUAL must abort partial frame");
  $display("PASS mode AUTO -> MANUAL midcapture aborted samples=%0d",auto_sample_writes);
  monitor_uart=1;#2.731;
  // 发送一段真实 NFR 上传后切到 DIAG；不能保留 frame_valid 或继续写 RAM。
  for(integer i=0;i<1000;i=i+1)send_byte(frames[i]);
  if(!dut.manual_transport.packet_active||manual_sample_writes<900||fv)$fatal(1,"partial manual upload setup");
  @(negedge clk);#1;manual_mode=0;diagnostic_mode=1;
  repeat(5)@(negedge clk);
  if(fv||accepted||dut.manual_transport.packet_active||dut.auto_busy)$fatal(1,"MANUAL to DIAG clears partial upload");
  for(integer i=1000;i<1032;i=i+1)send_byte(frames[i]);
  $display("PASS mode MANUAL -> DIAG midupload invalidated frame and ignored incoming UART/video");
  @(negedge clk);#1;diagnostic_mode=0;manual_mode=1;
  repeat(5)@(negedge clk);
  if(fv||accepted||dut.manual_transport.packet_active)$fatal(1,"DIAG to MANUAL must start empty");
  manual_sample_writes=0;#2.731;
  for(integer k=0;k<2;k=k+1)begin
   active_case=k;
   for(integer i=0;i<19212;i=i+1)send_byte(frames[k*19212+i]);
   wait(replies==k*3+1);#2000;check_reply(100+k,1);
   if(!fv||frame_id!==100+k)$fatal(1,"frame ACK metadata");
   for(integer i=0;i<21;i=i+1)send_byte(segments[k*21+i]);
   wait(replies==k*3+2);#2000;check_segment_reply(200+k);
   character_from_fpga_reply(300+k,100+k);
   for(integer i=0;i<25;i=i+1)send_byte(characters[i]);
   wait(replies==k*3+3);#2000;check_reply(300+k,0);
   if(seg_starts!=k+1||seg_completions!=k+1||norm_starts!=k+1||core_starts!=k+1||completions!=k+1||accepted!=3*(k+1)||crc_errors||rx_errors)$fatal(1,"chain counters");
   $display("PASS actual wrapper manual chain case=%0d boxes=%0d pixels=768 signed_scores=36 seg_cycles=%0d norm_cycles=%0d cnn_cycles=%0d",k,counts[k],saved_sc,saved_nc,saved_cc);
  end
  if(manual_sample_writes!=38400||ignored_camera_frames<2||dut.completed_frames!=0)$fatal(1,"live camera must not change manual frame RAM/count");
  $display("PASS mode DIAG -> MANUAL fresh upload recovery camera_frames_ignored=%0d manual_pixels=%0d",ignored_camera_frames,manual_sample_writes);
  $display("PASS tb_auto_manual_chain 2 real frames flags0/3 all boxes 1536 normalized pixels 72 signed scores 2464 response bytes actual wrapper three mode transitions");$finish;
 end
 initial begin #500000000;$fatal(1,"global watchdog");end
endmodule

