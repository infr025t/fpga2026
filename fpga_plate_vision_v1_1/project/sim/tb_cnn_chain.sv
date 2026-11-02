`timescale 1ns/1ps
// 真实串行输入 -> 协议桥 -> 真实 CNN -> 串行输出；预期分数来自冻结 NumPy 黄金向量。
module tb_cnn_chain;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,rxd=1;
 wire txd,core_start,core_in_we,core_busy,core_done,score_valid;
 wire [9:0]core_in_addr;wire[7:0]core_in_data;wire[5:0]score_index;
 wire signed[31:0]score_data;
 wire[31:0]core_cycles,accepted,crc_errors,rx_errors;
 cnn_uart_bridge transport(.clk(clk),.rst(rst),.uart_rxd(rxd),.uart_txd(txd),
  .core_start(core_start),.core_in_we(core_in_we),.core_in_addr(core_in_addr),.core_in_data(core_in_data),
  .core_busy(core_busy),.core_done(core_done),.score_valid(score_valid),.score_index(score_index),
  .score_data(score_data),.core_cycles(core_cycles),.accepted(accepted),.crc_errors(crc_errors),.rx_errors(rx_errors));
 cnn_core recognizer(.clk(clk),.rst(rst),.start(core_start),.in_we(core_in_we),
  .in_addr(core_in_addr),.in_data(core_in_data),.busy(core_busy),.done(core_done),
  .score_valid(score_valid),.score_index(score_index),.score_data(score_data),.cycles(core_cycles));
 reg[7:0]inputs[0:12*768-1];reg[31:0]scores[0:12*36-1];
 reg[7:0]request[0:779],reply[0:159],expected_reply[0:159];
 reg[7:0]sampled;
 integer launched=0,completed=0,response_count=0,reply_index=0;
 integer observed_cycles=0,completed_cycles=0,writes=0,active_case=0;
 always @(posedge clk)if(!rst)begin
  if(core_in_we)begin
   if(core_busy || core_in_addr!==writes[9:0])$fatal(1,"chain input address/busy violation");
   if(core_in_data!==inputs[active_case*768+writes])$fatal(1,"chain input data mismatch addr=%0d",writes);
   writes=writes+1;
  end
  if(core_start)begin
   if(writes!=768)$fatal(1,"chain launch before full input");
   launched=launched+1;observed_cycles=0;
  end
  if(core_busy)observed_cycles=observed_cycles+1;
  if(score_valid && score_data!==scores[active_case*36+score_index])
   $fatal(1,"chain core boundary mismatch case=%0d class=%0d got=%h expected=%h",active_case,score_index,score_data,scores[active_case*36+score_index]);
  if(core_done)begin
   completed=completed+1;completed_cycles=observed_cycles;
   if(core_cycles!==observed_cycles)$fatal(1,"chain cycle count differs from measured clocks");
  end
 end
 function automatic[31:0]crc_byte(input[31:0]crc,input[7:0]b);
  reg[31:0]v;integer k;
  begin v=crc^b;for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 // 独立时间采样，不复用被测 uart_fast_rx，以免相同缺陷互相掩盖。
 initial forever begin
  @(negedge txd);
  if(completed<=response_count)$fatal(1,"response started before real CNN completed");
  #(83.333333*1.5);
  for(integer b=0;b<8;b=b+1)begin sampled[b]=txd;#83.333333;end
  if(txd!==1'b1)$fatal(1,"chain TX invalid stop bit");
  reply[reply_index]=sampled;reply_index=reply_index+1;
  if(reply_index==160)begin reply_index=0;response_count=response_count+1;end
 end
 task automatic send_byte(input[7:0]value);
  begin
   rxd=0;#83.333333;
   for(integer b=0;b<8;b=b+1)begin rxd=value[b];#83.333333;end
   rxd=1;#83.333333;
  end
 endtask
 task automatic run_case(input integer case_id,input[31:0]seq,input integer job);
  reg[31:0]crc;
  begin
   active_case=case_id;writes=0;
   request[0]="C";request[1]="N";request[2]="N";request[3]="1";
   for(integer j=0;j<4;j=j+1)request[4+j]=seq>>(j*8);
   for(integer j=0;j<768;j=j+1)request[8+j]=inputs[case_id*768+j];
   crc=32'hffffffff;for(integer j=0;j<776;j=j+1)crc=crc_byte(crc,request[j]);crc=~crc;
   for(integer j=0;j<4;j=j+1)request[776+j]=crc>>(j*8);
   // 780 字节完全连续，无人为插入字节间隙。
   for(integer j=0;j<780;j=j+1)send_byte(request[j]);
   begin:response_wait
    for(integer timeout=0;timeout<1500000;timeout=timeout+1)begin
     @(negedge clk);if(response_count==job)disable response_wait;
    end
    $fatal(1,"chain response timeout case=%0d",case_id);
   end
   if(launched!=job || completed!=job || accepted!=job || crc_errors!=0 || rx_errors!=0)
    $fatal(1,"chain job/error counter mismatch");
   expected_reply[0]="C";expected_reply[1]="N";expected_reply[2]="R";expected_reply[3]="1";
   for(integer j=0;j<4;j=j+1)begin
    expected_reply[4+j]=seq>>(j*8);expected_reply[8+j]=completed_cycles>>(j*8);
   end
   for(integer j=0;j<36;j=j+1)
    for(integer b=0;b<4;b=b+1)expected_reply[12+j*4+b]=scores[case_id*36+j]>>(b*8);
   crc=32'hffffffff;for(integer j=0;j<156;j=j+1)crc=crc_byte(crc,expected_reply[j]);crc=~crc;
   for(integer j=0;j<4;j=j+1)expected_reply[156+j]=crc>>(j*8);
   for(integer j=0;j<160;j=j+1)
    if(reply[j]!==expected_reply[j])$fatal(1,"chain response mismatch case=%0d byte=%0d got=%h expected=%h",case_id,j,reply[j],expected_reply[j]);
   $display("PASS chain case=%0d seq=%h scores=36 bytes=160 cycles=%0d CRC=%h",case_id,seq,completed_cycles,crc);
   // 最后一字节 stop 剩余半位以及发送器 drain；下一包不复位核心。
   #1000;
  end
 endtask
 initial begin
  $readmemh("vectors_input.hex",inputs);$readmemh("vectors_scores.hex",scores);
  #100;@(negedge clk);rst=0;#2.731;
  run_case(0,32'h89abcdef,1);
  run_case(9,32'h01234567,2);
  if(response_count!=2 || reply_index!=0)$fatal(1,"chain extra response data");
  $display("PASS tb_cnn_chain real_char_0 then seeded_random: 72 golden scores / 320 exact response bytes");
  $finish;
 end
 initial begin #40000000;$fatal(1,"chain global watchdog");end
endmodule
