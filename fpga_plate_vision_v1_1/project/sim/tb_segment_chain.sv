`timescale 1ns/1ps
// 原始整帧串行输入 -> 实际归一化 -> 冻结CNN -> 串行回传，独立NumPy黄金比对。
module tb_segment_chain;
 reg clk=0;always #5 clk=~clk;reg rst=1,rxd=1;wire txd;
 wire ss,sb,sdone,swe;wire[7:0]serr,sx,sy,sw,sh,srd;wire[31:0]scycles;
 wire[5:0]sindex;wire[6:0]scount;wire[14:0]sra;
 wire fw,ns,cs,iw,wr,nb,nd,ne,pw,cb,cd,sv,fv;
 wire[14:0]fa;wire[7:0]fd,id,pd;wire[9:0]ia,pa;wire[5:0]si;wire signed[31:0]sd;
 wire[7:0]bx,by,bw,bh,rx0,ry0,rx1,ry1;wire[1:0]flags;
 wire[31:0]nc,cc,accepted,crc_errors,rx_errors,frame_id;
 norm_uart_bridge dut(.clk(clk),.rst(rst),.uart_rxd(rxd),.uart_txd(txd),.frame_we(fw),.frame_addr(fa),.frame_data(fd),
 .norm_start(ns),.box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),.roi_x0(rx0),.roi_y0(ry0),.roi_x1(rx1),.roi_y1(ry1),.flags(flags),
 .norm_busy(nb),.norm_done(nd),.norm_error(ne),.norm_cycles(nc),.norm_pixel_we(pw),.norm_pixel_addr(pa),.norm_pixel_data(pd),
 .core_start(cs),.core_in_we(iw),.core_in_addr(ia),.core_in_data(id),.core_busy(cb),.core_done(cd),.score_valid(sv),.score_index(si),.score_data(sd),.core_cycles(cc),
 .seg_start(ss),.seg_busy(sb),.seg_done(sdone),.seg_error(serr),.seg_cycles(scycles),
 .seg_box_we(swe),.seg_box_index(sindex),.seg_box_x(sx),.seg_box_y(sy),.seg_box_w(sw),.seg_box_h(sh),.seg_box_count(scount),
 .worker_reset(wr),.accepted(accepted),.crc_errors(crc_errors),.rx_errors(rx_errors),.frame_valid(fv),.frame_id(frame_id));
 char_segmenter segmenter(.clk(clk),.rst(rst|wr),.start(ss),
 .roi_x0(rx0),.roi_y0(ry0),.roi_x1(rx1),.roi_y1(ry1),.flags(flags),
 .busy(sb),.done(sdone),.error(serr),.cycles(scycles),.frame_read_addr(sra),.frame_read_data(srd),
 .box_we(swe),.box_index(sindex),.box_x(sx),.box_y(sy),.box_w(sw),.box_h(sh),.box_count(scount));
 char_normalizer #(.ENABLE_SCAN(1)) normalizer(.clk(clk),.rst(rst|wr),.start(ns),.frame_we(fw),.frame_addr(fa),.frame_data(fd),
 .scan_en(sb),.scan_addr(sra),.scan_data(srd),
 .box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),.roi_x0(rx0),.roi_y0(ry0),.roi_x1(rx1),.roi_y1(ry1),.flags(flags),
 .busy(nb),.done(nd),.error(ne),.cycles(nc),.pixel_we(pw),.pixel_addr(pa),.pixel_data(pd));
 cnn_core recognizer(.clk(clk),.rst(rst|wr),.start(cs),.in_we(iw),.in_addr(ia),.in_data(id),.busy(cb),.done(cd),.score_valid(sv),.score_index(si),.score_data(sd),.cycles(cc));
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
  @(negedge txd);#(83.333333*1.5);
  for(integer k=0;k<8;k=k+1)begin sampled[k]=txd;#83.333333;end
  if(txd!==1)$fatal(1,"TX stop bit");reply[rx_count]=sampled;rx_count=rx_count+1;
  if(rx_count==3)expected_size=(reply[1]=="F")?16:((reply[1]=="S")?280:936);
  if(rx_count==expected_size && expected_size!=0)begin replies=replies+1;rx_count=0;expected_size=0;end
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
  #100;@(negedge clk);rst=0;#2.731;
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
   $display("PASS real segment chain case=%0d boxes=%0d pixels=768 signed_scores=36 seg_cycles=%0d norm_cycles=%0d cnn_cycles=%0d",k,counts[k],saved_sc,saved_nc,saved_cc);
  end
  $display("PASS tb_segment_chain 2 real frames flags0/3 all boxes then FPGA-first-box NCH 1536 pixels 72 signed scores 2464 response bytes shared frame RAM");$finish;
 end
 initial begin #500000000;$fatal(1,"global watchdog");end
endmodule
