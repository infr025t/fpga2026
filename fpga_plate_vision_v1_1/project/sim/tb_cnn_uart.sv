`timescale 1ns/1ps
// 协议测试独立驱动异步串行线，不使用被测接收器解码返回数据。
module tb_cnn_uart;
 reg clk=0; always #5 clk=~clk;
 reg rst=1, rxd=1;
 wire txd,start,in_we; wire [9:0] in_addr; wire [7:0] in_data;
 reg busy=0,done=0,sv=0; reg [5:0] si=0; reg signed [31:0] sd=0;
 reg [31:0] cycles=32'h12345678;
 wire [31:0] accepted,crc_errors,rx_errors;
 cnn_uart_bridge #(.RX_TIMEOUT_CYCLES(500)) dut(
  .clk(clk),.rst(rst),.uart_rxd(rxd),.uart_txd(txd),.core_start(start),
  .core_in_we(in_we),.core_in_addr(in_addr),.core_in_data(in_data),
  .core_busy(busy),.core_done(done),.score_valid(sv),.score_index(si),
  .score_data(sd),.core_cycles(cycles),.accepted(accepted),
  .crc_errors(crc_errors),.rx_errors(rx_errors));
 reg [7:0] pixels[0:767],request[0:779],reply[0:159];
 integer writes=0, launches=0,replies=0,rx_count=0,mock_count=0;
 integer expected_seed=0,writes_before_noise=0;
 reg [7:0] sampled;
 real bit_period=83.333333;
 function automatic [31:0] crc_byte(input [31:0] c,input [7:0] b);
  reg [31:0] v; integer k;
  begin v=c^b;for(k=0;k<8;k=k+1) v=v[0] ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end
 endfunction
 function automatic [31:0] mock_score(input integer k);
  mock_score=(k%2) ? -32'sd7654321-k*76543 : 32'sd1234567+k*87654;
 endfunction
 function automatic [7:0] pixel(input integer k,input integer seed);
  pixel=(k*37+seed*19)^(k>>3);
 endfunction
 // Mock 只替代计算核心；输入写地址、完整性和有效启动均在协议边界核对。
 always @(posedge clk) begin
  if(rst)begin busy<=0;done<=0;sv<=0;mock_count<=0;end
  else begin
   done<=0;sv<=0;
   if(in_we)begin
    if(busy) $fatal(1,"input overwrite while core busy");
    if(in_addr>=768) $fatal(1,"input address overflow");
    pixels[in_addr]=in_data;writes=writes+1;
   end
   if(start)begin
    if(busy) $fatal(1,"start while busy");
    for(integer k=0;k<768;k=k+1)
     if(pixels[k]!==pixel(k,expected_seed)) $fatal(1,"input mismatch addr=%0d",k);
    launches=launches+1;busy<=1;mock_count<=0;
   end
   else if(busy)begin
    mock_count<=mock_count+1;
    // 倒序、有气泡，最后分数与 done 同拍，检验完整位图而非简单计数。
    if(mock_count==200)begin sv<=1;si<=35;sd<=mock_score(35);end
    if(mock_count>=400 && mock_count<508 && mock_count%3==1)begin
     sv<=1;si<=35-(mock_count-400)/3;sd<=mock_score(35-(mock_count-400)/3);
    end
    if(mock_count==505)begin done<=1;busy<=0;end
   end
  end
 end
 // 独立时间采样 12 Mbaud；按 start 边沿定位，核对 stop 位。
 initial forever begin
  @(negedge txd);
  #(83.333333*1.5);
  for(integer b=0;b<8;b=b+1)begin sampled[b]=txd;#83.333333;end
  if(txd!==1'b1)$fatal(1,"TX stop bit invalid");
  reply[rx_count]=sampled;rx_count=rx_count+1;
  if(rx_count==160)begin rx_count=0;replies=replies+1;end
 end
 task automatic send_byte(input [7:0] value,input bit bad_stop=0);
  begin
   rxd=0;#(bit_period);
   for(integer b=0;b<8;b=b+1)begin rxd=value[b];#(bit_period);end
   rxd=!bad_stop;#(bit_period);rxd=1;
  end
 endtask
 task automatic build_request(input [31:0] seq,input integer seed,input bit bad_crc=0);
  reg[31:0] crc;
  begin
   request[0]="C";request[1]="N";request[2]="N";request[3]="1";
   for(integer j=0;j<4;j=j+1)request[4+j]=seq>>(j*8);
   for(integer j=0;j<768;j=j+1)request[8+j]=pixel(j,seed);
   crc=32'hffffffff;
   for(integer j=0;j<776;j=j+1)crc=crc_byte(crc,request[j]);
   crc=~crc;if(bad_crc)crc=crc^32'h80000100;
   for(integer j=0;j<4;j=j+1)request[776+j]=crc>>(j*8);
  end
 endtask
 task automatic send_request(input integer count=780);
  for(integer j=0;j<count;j=j+1)send_byte(request[j]);
 endtask
 task automatic check_reply(input [31:0] seq,input integer want_replies);
  reg[31:0] crc,got,want;
  begin
   begin:response_wait
    for(integer timeout=0;timeout<25000;timeout=timeout+1)begin
     @(posedge clk);if(replies==want_replies)disable response_wait;
    end
    $fatal(1,"response timeout replies=%0d launches=%0d",replies,launches);
   end
   if({reply[0],reply[1],reply[2],reply[3]}!==32'h434e5231)$fatal(1,"response magic mismatch");
   for(integer j=0;j<4;j=j+1)begin
    if(reply[4+j]!==((seq>>(8*j))&255))$fatal(1,"sequence mismatch");
    if(reply[8+j]!==((cycles>>(8*j))&255))$fatal(1,"cycles mismatch");
   end
   for(integer j=0;j<36;j=j+1)begin
    got={reply[15+j*4],reply[14+j*4],reply[13+j*4],reply[12+j*4]};want=mock_score(j);
    if(got!==want)$fatal(1,"score mismatch index=%0d got=%h want=%h",j,got,want);
   end
   crc=32'hffffffff;for(integer j=0;j<156;j=j+1)crc=crc_byte(crc,reply[j]);
   got={reply[159],reply[158],reply[157],reply[156]};
   if(got!==~crc)$fatal(1,"response CRC mismatch");
   #1000;
  end
 endtask
 initial begin
  #100;@(negedge clk);rst=0;#3.127;
  // 该固定值用 Python zlib.crc32 独立计算，避免 TB 与 RTL 共用错误 CRC 约定。
  build_request(32'h44332211,1);
  if({request[779],request[778],request[777],request[776]}!==32'hbf310420)$fatal(1,"CRC fixture differs from Python zlib");
  // 错 CRC 必须拒绝启动，并允许下一包正常工作。
  build_request(32'h44332211,1,1);send_request();#1000;
  if(launches!=0 || crc_errors!=1)$fatal(1,"bad CRC launched or not counted");
  $display("PASS bad CRC rejected");
  // 半包超时后，重叠 magic 前缀也必须恢复。
  build_request(32'h44332212,2);send_request(100);#6000;
  if(launches!=0 || rx_errors!=1)$fatal(1,"partial timeout failed");
  send_byte("C");send_byte("C");send_byte("N");send_byte("C");
  expected_seed=3;build_request(32'hfedcba98,3);send_request();
  check_reply(32'hfedcba98,1);
  if(accepted!=1 || launches!=1)$fatal(1,"valid packet accepted count");
  $display("PASS timeout / overlap resync / exact response with CRC");
  // 非法 stop 位使整包失效，随后高电平恢复。
  build_request(9,4);send_request(21);send_byte(8'h00,1);#6000;
  if(launches!=1 || rx_errors!=2)$fatal(1,"framing error failed");
  // 多种异步相位、逐字节无间隙，以及 +/-2% 波特偏差。
  for(integer n=0;n<10;n=n+1)begin
   bit_period=(n==8)?81.666667:(n==9)?85.0:83.333333;
   @(negedge clk);#(n+0.37);
   expected_seed=10+n;build_request(100+n,10+n);send_request();
   // 核心计算期间收到的字节必须丢弃，不得污染请求或输入 RAM。
   writes_before_noise=writes;
   send_byte("C");send_byte("N");send_byte("N");send_byte("1");
   // 噪声延伸到响应发送阶段；核心 busy 此时可能已撤销。
   for(integer j=0;j<36;j=j+1)send_byte(j);
   check_reply(100+n,2+n);
   if(writes!=writes_before_noise)$fatal(1,"input changed while bridge busy");
  end
  if(accepted!=11 || launches!=11 || crc_errors!=1 || rx_errors!=2)
   $fatal(1,"final counters accepted=%0d launches=%0d crc=%0d rx=%0d",accepted,launches,crc_errors,rx_errors);
  $display("PASS phases 0..9 ns, contiguous bytes, +/-2 percent baud, busy discard");
  // 模式切换的外部 reset：半包和运算均应中止，不能漏出旧响应。
  bit_period=83.333333;build_request(777,30);send_request(88);
  @(negedge clk);rst=1;#100;@(negedge clk);rst=0;#1000;
  if(accepted!=0 || rx_errors!=0)$fatal(1,"partial reset counters");
  expected_seed=31;build_request(778,31);send_request();
  if(!busy)$fatal(1,"reset-abort fixture did not reach running core");
  @(negedge clk);rst=1;#100;@(negedge clk);rst=0;#10000;
  if(replies!=11 || accepted!=0 || busy)$fatal(1,"reset did not abort active computation");
  expected_seed=32;build_request(779,32);send_request();check_reply(779,12);
  if(accepted!=1 || crc_errors!=0 || rx_errors!=0)$fatal(1,"restart after reset failed");
  $display("PASS reset partial packet / reset active core / restart");
  $display("PASS tb_cnn_uart accepted=%0d crc_errors=%0d rx_errors=%0d",accepted,crc_errors,rx_errors);
  $finish;
 end
 initial begin #20000000;$fatal(1,"global watchdog");end
endmodule
