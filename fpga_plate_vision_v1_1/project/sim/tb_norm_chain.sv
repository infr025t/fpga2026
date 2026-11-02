`timescale 1ns/1ps
// 原始整帧串行输入 -> 实际归一化 -> 冻结CNN -> 串行回传，独立NumPy黄金比对。
module tb_norm_chain;
 reg clk=0;always #5 clk=~clk;reg rst=1,rxd=1;wire txd;
 wire fw,ns,cs,iw,wr,nb,nd,ne,pw,cb,cd,sv,fv;
 wire[14:0]fa;wire[7:0]fd,id,pd;wire[9:0]ia,pa;wire[5:0]si;wire signed[31:0]sd;
 wire[7:0]bx,by,bw,bh,rx0,ry0,rx1,ry1;wire[1:0]flags;
 wire[31:0]nc,cc,accepted,crc_errors,rx_errors,frame_id;
 norm_uart_bridge dut(.clk(clk),.rst(rst),.uart_rxd(rxd),.uart_txd(txd),.frame_we(fw),.frame_addr(fa),.frame_data(fd),
 .norm_start(ns),.box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),.roi_x0(rx0),.roi_y0(ry0),.roi_x1(rx1),.roi_y1(ry1),.flags(flags),
 .norm_busy(nb),.norm_done(nd),.norm_error(ne),.norm_cycles(nc),.norm_pixel_we(pw),.norm_pixel_addr(pa),.norm_pixel_data(pd),
 .core_start(cs),.core_in_we(iw),.core_in_addr(ia),.core_in_data(id),.core_busy(cb),.core_done(cd),.score_valid(sv),.score_index(si),.score_data(sd),.core_cycles(cc),
 .worker_reset(wr),.accepted(accepted),.crc_errors(crc_errors),.rx_errors(rx_errors),.frame_valid(fv),.frame_id(frame_id));
 char_normalizer normalizer(.clk(clk),.rst(rst|wr),.start(ns),.frame_we(fw),.frame_addr(fa),.frame_data(fd),
 .box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),.roi_x0(rx0),.roi_y0(ry0),.roi_x1(rx1),.roi_y1(ry1),.flags(flags),
 .busy(nb),.done(nd),.error(ne),.cycles(nc),.pixel_we(pw),.pixel_addr(pa),.pixel_data(pd));
 cnn_core recognizer(.clk(clk),.rst(rst|wr),.start(cs),.in_we(iw),.in_addr(ia),.in_data(id),.busy(cb),.done(cd),.score_valid(sv),.score_index(si),.score_data(sd),.cycles(cc));
 reg[7:0]frames[0:38423],characters[0:49],pixels[0:1535],reply[0:935],sampled;
 reg[31:0]scores[0:71];integer rx_count=0,replies=0,expected_size=0,active_case=0,writes=0;
 integer norm_starts=0,core_starts=0,completions=0,observed_nc=0,observed_cc=0,saved_nc=0,saved_cc=0;
 reg[35:0]score_mask=0;
 function automatic[31:0]crc_byte(input[31:0]c,input[7:0]b);
  reg[31:0]v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 always @(posedge clk)if(!rst)begin
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
  if(rx_count==3)expected_size=(reply[1]=="F")?16:936;
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
 initial begin
  $readmemh("frames.hex",frames);$readmemh("characters.hex",characters);$readmemh("pixels.hex",pixels);$readmemh("scores.hex",scores);
  #100;@(negedge clk);rst=0;#2.731;
  for(integer k=0;k<2;k=k+1)begin
   active_case=k;
   for(integer i=0;i<19212;i=i+1)send_byte(frames[k*19212+i]);
   wait(replies==k*2+1);#2000;check_reply(100+k,1);
   if(!fv||frame_id!==100+k)$fatal(1,"frame ACK metadata");
   for(integer i=0;i<25;i=i+1)send_byte(characters[k*25+i]);
   wait(replies==k*2+2);#2000;check_reply(200+k,0);
   if(norm_starts!=k+1||core_starts!=k+1||completions!=k+1||accepted!=2*(k+1)||crc_errors||rx_errors)$fatal(1,"chain counters");
   $display("PASS real norm chain case=%0d pixels=768 scores=36 bytes=936 norm_cycles=%0d cnn_cycles=%0d",k,saved_nc,saved_cc);
  end
  $display("PASS tb_norm_chain 2 real frames flags0/3 1536 pixels 72 scores 1904 response bytes");$finish;
 end
 initial begin #150000000;$fatal(1,"global watchdog");end
endmodule
