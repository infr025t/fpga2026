`timescale 1ns/1ps
module tb_norm_uart_bridge;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,rxd=1;wire txd;
 wire fw,ns,cs,iw,wr,fv;wire[14:0]fa;wire[7:0]fd,id;wire[9:0]ia;
 wire[7:0]bx,by,bw,bh,rx0,ry0,rx1,ry1;wire[1:0]flags;
 wire[31:0]accepted,crc_errors,rx_errors,frame_id;
 reg nb=0,nd=0,ne=0,pw=0,cb=0,cd=0,sv=0;
 reg[9:0]pa=0;reg[7:0]pd=0;reg[5:0]si=0;reg signed[31:0]sd=0;
 norm_uart_bridge #(.RX_TIMEOUT_CYCLES(500),.NORM_TIMEOUT_CYCLES(6000),.CNN_TIMEOUT_CYCLES(6000)) dut(
 .clk(clk),.rst(rst),.uart_rxd(rxd),.uart_txd(txd),.frame_we(fw),.frame_addr(fa),.frame_data(fd),
 .norm_start(ns),.box_x(bx),.box_y(by),.box_w(bw),.box_h(bh),.roi_x0(rx0),.roi_y0(ry0),.roi_x1(rx1),.roi_y1(ry1),.flags(flags),
 .norm_busy(nb),.norm_done(nd),.norm_error(ne),.norm_cycles(32'd12345),.norm_pixel_we(pw),.norm_pixel_addr(pa),.norm_pixel_data(pd),
 .core_start(cs),.core_in_we(iw),.core_in_addr(ia),.core_in_data(id),.core_busy(cb),.core_done(cd),.score_valid(sv),.score_index(si),.score_data(sd),.core_cycles(32'd67890),
 .seg_start(),.seg_busy(1'b0),.seg_done(1'b0),.seg_error(8'd0),.seg_cycles(32'd0),
 .seg_box_we(1'b0),.seg_box_index(6'd0),.seg_box_x(8'd0),.seg_box_y(8'd0),.seg_box_w(8'd0),.seg_box_h(8'd0),.seg_box_count(7'd0),
 .worker_reset(wr),.accepted(accepted),.crc_errors(crc_errors),.rx_errors(rx_errors),.frame_valid(fv),.frame_id(frame_id));

 real bit_period=83.333333;
 reg[7:0]request[0:19211],reply[0:935],sampled;
 integer rx_count=0,replies=0,expected_size=0,ncount=0,ccount=0;
 integer norm_launches=0,core_launches=0,frame_writes=0,pixel_writes=0,worker_resets=0;
 integer mode=0,base_replies,base_accepted,base_crc,base_rx,base_norm,base_core;
 reg[31:0]check_crc;integer j;
 function automatic[31:0]crc_byte(input[31:0]c,input[7:0]b);
  reg[31:0]v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 function automatic[7:0]pixel(input integer k);pixel=(k*37)^(k>>3);endfunction
 function automatic[31:0]score(input integer k);score=(k%2)?-7654321-k*76543:1234567+k*87654;endfunction
 // 独立位时间采样，不复用被测UART接收器。
 initial forever begin
  @(negedge txd);#(bit_period*1.5);
  for(integer k=0;k<8;k=k+1)begin sampled[k]=txd;#(bit_period);end
  if(txd!==1)$fatal(1,"TX stop bit");
  reply[rx_count]=sampled;rx_count=rx_count+1;
  if(rx_count==3)expected_size=(reply[1]=="F")?16:936;
  if(rx_count==expected_size && expected_size!=0)begin replies=replies+1;rx_count=0;expected_size=0;end
 end
 // Mock仅替代运算，模拟有气泡、顺序像素、倒序分数及done/最后score同拍。
 always @(posedge clk)begin
  if(rst||wr)begin nb<=0;nd<=0;pw<=0;cb<=0;cd<=0;sv<=0;ncount<=0;ccount<=0;ne<=0;
   if(wr)worker_resets=worker_resets+1;
  end else begin
   nd<=0;pw<=0;cd<=0;sv<=0;
   if(fw)begin
    if(fa>=19200 || fd!==pixel(fa))$fatal(1,"frame write addr=%0d data=%0d",fa,fd);
    frame_writes=frame_writes+1;
   end
   if(iw)begin
    if(cb || ia!==pixel_writes || id!==pixel(ia))$fatal(1,"CNN pixel forwarding addr=%0d expected=%0d",ia,pixel_writes);
    pixel_writes=pixel_writes+1;
   end
   if(ns)begin
    if(nb||cb)$fatal(1,"normalizer launch while busy");
    norm_launches=norm_launches+1;nb<=1;ncount<=0;pixel_writes=0;
    if(bx!==3||by!==4||bw!==10||bh!==20||rx0!==0||ry0!==0||rx1!==160||ry1!==120||flags!==3)$fatal(1,"descriptor mismatch");
   end else if(nb && mode!=1)begin
    ncount<=ncount+1;
    if(mode==3)begin ne<=1;nd<=1;nb<=0;end
    else if(ncount<2304 && ncount%3==0 && !(mode==4 && ncount==2301))begin
     pw<=1;pa<=ncount/3;pd<=pixel(ncount/3);
    end else if(ncount==2304)begin nd<=1;nb<=0;ne<=0;end
   end
   if(cs)begin
    if(nb||cb||pixel_writes!=768)$fatal(1,"bad CNN start count=%0d",pixel_writes);
    core_launches=core_launches+1;cb<=1;ccount<=0;
   end else if(cb && mode!=2)begin
    ccount<=ccount+1;
    if(ccount==0)begin sv<=1;si<=35;sd<=score(35);end // 重复分数不能替代完整位图。
    if(ccount>=10 && ccount<118 && (ccount-10)%3==0)begin
     sv<=(mode!=5 || ccount!=115);si<=35-(ccount-10)/3;sd<=score(35-(ccount-10)/3);
     if(ccount==115)begin cd<=1;cb<=0;end
    end
   end
  end
 end
 task automatic send_byte(input[7:0]b);
  begin rxd=0;#(bit_period);for(integer k=0;k<8;k=k+1)begin rxd=b[k];#(bit_period);end rxd=1;#(bit_period);end
 endtask
 task automatic build_request(input bit isframe,input integer seq,input integer fid,input integer f);
  reg[31:0]c;integer n;
  begin
   request[0]="N";request[1]=isframe?"F":"C";request[2]=isframe?"R":"H";request[3]="1";
   for(integer k=0;k<4;k=k+1)request[4+k]=seq>>(k*8);
   if(isframe)begin n=19208;for(integer k=0;k<19200;k=k+1)request[k+8]=pixel(k);end
   else begin
    n=21;for(integer k=0;k<4;k=k+1)request[8+k]=fid>>(k*8);
    request[12]=3;request[13]=4;request[14]=10;request[15]=20;
    request[16]=0;request[17]=0;request[18]=160;request[19]=120;request[20]=f;
   end
   c=32'hffffffff;for(integer k=0;k<n;k=k+1)c=crc_byte(c,request[k]);c=~c;
   for(integer k=0;k<4;k=k+1)request[n+k]=c>>(k*8);
  end
 endtask
 task automatic send_packet(input integer n);begin for(integer k=0;k<n;k=k+1)send_byte(request[k]);end endtask
 task automatic expect_reply(input integer before_count,input integer seq,input integer st,input bit ack);
  integer size;reg[31:0]c,got;begin
   while(replies<=before_count)@(posedge clk);#2000;
   if(replies!=before_count+1)$fatal(1,"extra reply");size=ack?16:936;
   if(reply[0]!=="N"||reply[1]!==(ack?"F":"R")||reply[2]!==(ack?"A":"S")||reply[3]!=="1")$fatal(1,"reply magic");
   got={reply[7],reply[6],reply[5],reply[4]};if(got!==seq)$fatal(1,"reply sequence");
   got={reply[11],reply[10],reply[9],reply[8]};if(got!==st)$fatal(1,"reply status got=%0d expected=%0d",got,st);
   c=32'hffffffff;for(integer k=0;k<size-4;k=k+1)c=crc_byte(c,reply[k]);
   got={reply[size-1],reply[size-2],reply[size-3],reply[size-4]};if(got!==~c)$fatal(1,"reply CRC");
   if(!ack)begin
    if(st==0)begin
     got={reply[15],reply[14],reply[13],reply[12]};if(got!==12345)$fatal(1,"norm cycles");
     got={reply[19],reply[18],reply[17],reply[16]};if(got!==67890)$fatal(1,"CNN cycles");
     for(integer k=0;k<768;k=k+1)if(reply[20+k]!==pixel(k))$fatal(1,"reply pixel %0d",k);
     for(integer k=0;k<36;k=k+1)begin
      got={reply[791+4*k],reply[790+4*k],reply[789+4*k],reply[788+4*k]};if(got!==score(k))$fatal(1,"reply score %0d",k);
     end
    end else begin
     for(integer k=20;k<932;k=k+1)if(reply[k]!==0)$fatal(1,"error payload not zero %0d",k);
     if(st==1)for(integer k=12;k<20;k=k+1)if(reply[k]!==0)$fatal(1,"unstarted cycles not zero");
    end
   end
  end endtask
 task automatic character(input integer seq,input integer fid,input integer f,input integer st);
  integer b;begin b=replies;build_request(0,seq,fid,f);send_packet(25);expect_reply(b,seq,st,0);end
 endtask
 task automatic upload(input integer seq);
  integer b;begin b=replies;build_request(1,seq,0,0);send_packet(19212);expect_reply(b,seq,0,1);
   if(!fv||frame_id!==seq)$fatal(1,"frame validity/id");end
 endtask
 initial begin
  #100;@(negedge clk);rst=0;#100;
  if(fv!==0||accepted!==0)$fatal(1,"reset values");
  character(1,10,3,1);if(norm_launches!=0)$fatal(1,"missing frame launched");
  // 坏CRC整帧不可确认或使用。
  base_replies=replies;build_request(1,10,0,0);request[19211]=request[19211]^8'h01;send_packet(19212);#10000;
  if(crc_errors!=1||fv||replies!=base_replies)$fatal(1,"bad frame CRC");
  upload(10);if(frame_writes!=38400)$fatal(1,"frame byte count %0d",frame_writes);
  character(2,9,3,1);character(3,10,128,2);
  // 字符CRC错不废弃已确认帧。
  base_replies=replies;build_request(0,4,10,3);request[24]=request[24]^1;send_packet(25);#10000;
  if(crc_errors!=2||!fv||replies!=base_replies)$fatal(1,"bad char CRC");
  // 推理忙时插入完整请求，应被丢弃；回传每字节都检查。
  base_replies=replies;build_request(0,5,10,3);send_packet(25);
  wait(nb);build_request(0,999,10,3);send_packet(25);
  expect_reply(base_replies,5,0,0);#10000;
  if(norm_launches!=1||core_launches!=1||accepted!=5)$fatal(1,"busy request accepted %0d",accepted);
  // 半包超时；识别上传magic即无效，不可沿用旧帧。
  base_replies=replies;base_rx=rx_errors;build_request(1,11,0,0);send_packet(100);#10000;
  if(fv||rx_errors!=base_rx+1||replies!=base_replies)$fatal(1,"frame partial timeout");
  character(6,10,3,1);
  upload(12);
  // normalizer显式描述符错误，零填充响应，CNN不得启动。
  mode=3;base_core=core_launches;character(7,12,3,2);
  if(core_launches!=base_core)$fatal(1,"invalid norm started CNN");
  // 少一个归一化像素也不得启动CNN。
  mode=4;base_core=core_launches;character(71,12,3,2);
  if(core_launches!=base_core)$fatal(1,"truncated pixels started CNN");
  // norm与CNN分别卡住；强制reset一次并废弃帧。
  mode=1;character(8,12,3,3);
  if(fv||worker_resets!=1)$fatal(1,"norm watchdog recovery");
  mode=0;upload(13);mode=2;character(9,13,3,3);
  if(fv||worker_resets!=2)$fatal(1,"CNN watchdog recovery");
  mode=0;upload(14);character(10,14,3,0);
  // done已经到达但缺一项分数：仍须watchdog，不能用重复分数凑数。
  mode=5;character(101,14,3,3);
  if(fv||worker_resets!=3)$fatal(1,"missing score watchdog");
  mode=0;upload(15);
  // 接收坏stop与前缀超时。
  base_rx=rx_errors;rxd=0;#(bit_period*12);rxd=1;#10000;
  if(rx_errors!=base_rx+1)$fatal(1,"framing error");
  base_rx=rx_errors;send_byte("N");#10000;if(rx_errors!=base_rx+1)$fatal(1,"magic timeout");
  // 外部复位取消进行中的worker，旧帧及计数不可泄漏。
  mode=1;build_request(0,11,15,3);send_packet(25);wait(nb);
  @(negedge clk);rst=1;repeat(5)@(negedge clk);rst=0;mode=0;#10000;
  if(fv||accepted!=0||crc_errors!=0||rx_errors!=0||nb||cb)$fatal(1,"active reset");
  character(12,14,3,1);
  // 上传中复位后尾部不得构成有效上传。
  base_replies=replies;build_request(1,16,0,0);send_packet(100);
  @(negedge clk);rst=1;repeat(5)@(negedge clk);rst=0;#10000;
  if(fv||accepted!=0||replies!=base_replies)$fatal(1,"partial upload reset");
  $display("PASS tb_norm_uart_bridge frameCRC charCRC partialtimeout missing/stale flags busy all936bytes norm/CNNwatchdog reset framing");$finish;
 end
 initial begin #200000000;$fatal(1,"global timeout");end
endmodule

