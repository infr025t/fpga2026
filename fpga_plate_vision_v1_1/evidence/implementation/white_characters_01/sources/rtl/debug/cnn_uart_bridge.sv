`timescale 1ns/1ps
module cnn_uart_bridge #(parameter integer RX_TIMEOUT_CYCLES=10000000)(
 input wire clk,rst,uart_rxd,output wire uart_txd,
 output reg core_start,core_in_we,output reg[9:0] core_in_addr,output reg[7:0] core_in_data,
 input wire core_busy,core_done,score_valid,input wire[5:0]score_index,
 input wire signed[31:0]score_data,input wire[31:0]core_cycles,
 output reg[31:0]accepted,crc_errors,rx_errors);
 localparam RECV=2'd0,RUN=2'd1,SEND=2'd2,DRAIN=2'd3;
 reg[1:0] state;
 wire rx_valid,rx_frame_error;wire[7:0]rx_data;
 uart_fast_rx receiver(.clk(clk),.rst(rst),.rx(uart_rxd),.valid(rx_valid),.data(rx_data),.framing_error(rx_frame_error));
 reg[2:0] magic_count;
 reg packet_active;
 reg[9:0] req_index;
 reg[31:0] rx_crc,received_crc,sequence_id,timeout_count;
 reg signed[31:0] scores[0:35];
 reg[35:0] score_mask;
 reg done_seen;
 reg[31:0] result_cycles;
 reg[7:0] tx_index;
 reg[31:0] tx_crc,response_crc;
 reg[7:0] tx_data;
 wire tx_ready;
 wire tx_valid=(state==SEND);
 uart_fast_tx transmitter(.clk(clk),.rst(rst),.valid(tx_valid),.data(tx_data),.ready(tx_ready),.tx(uart_txd));
 function automatic[31:0] crc_byte(input[31:0] c,input[7:0] b);
  reg[31:0] v;integer k;
  begin v=c^{24'b0,b};for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:(v>>1);crc_byte=v;end
 endfunction
 // 固定长度响应，字节序明确；分数在 SEND 期间冻结。
 always @*begin
  tx_data=0;
  case(tx_index)
   0:tx_data="C";1:tx_data="N";2:tx_data="R";3:tx_data="1";
   4,5,6,7:tx_data=sequence_id>>(8*(tx_index-4));
   8,9,10,11:tx_data=result_cycles>>(8*(tx_index-8));
   156,157,158,159:tx_data=response_crc>>(8*(tx_index-156));
   default:if(tx_index>=12 && tx_index<156)tx_data=scores[(tx_index-12)>>2]>>(8*(tx_index[1:0]));
  endcase
 end
 always @(posedge clk)begin
  if(rst)begin
   state<=RECV;core_start<=0;core_in_we<=0;core_in_addr<=0;core_in_data<=0;
   accepted<=0;crc_errors<=0;rx_errors<=0;magic_count<=0;packet_active<=0;
   req_index<=0;rx_crc<=32'hffffffff;received_crc<=0;sequence_id<=0;timeout_count<=0;
   score_mask<=0;done_seen<=0;result_cycles<=0;tx_index<=0;tx_crc<=32'hffffffff;response_crc<=0;
  end else begin
   core_start<=0;core_in_we<=0;
   case(state)
    RECV:begin
     if(core_busy)begin packet_active<=0;magic_count<=0;timeout_count<=0;end
     else if(rx_frame_error)begin
      rx_errors<=rx_errors+1'b1;packet_active<=0;magic_count<=0;timeout_count<=0;
     end else if(rx_valid)begin
      timeout_count<=0;
      if(!packet_active)begin
       // 前缀扫描支持 CCNN1 / CNCNN1 等重叠输入；失配 C 保留为新前缀。
       case(magic_count)
        0:if(rx_data=="C")begin magic_count<=1;rx_crc<=crc_byte(32'hffffffff,rx_data);end
        1:if(rx_data=="N")begin magic_count<=2;rx_crc<=crc_byte(rx_crc,rx_data);end
          else if(rx_data=="C")begin magic_count<=1;rx_crc<=crc_byte(32'hffffffff,rx_data);end else magic_count<=0;
        2:if(rx_data=="N")begin magic_count<=3;rx_crc<=crc_byte(rx_crc,rx_data);end
          else if(rx_data=="C")begin magic_count<=1;rx_crc<=crc_byte(32'hffffffff,rx_data);end else magic_count<=0;
        3:if(rx_data=="1")begin packet_active<=1;magic_count<=0;req_index<=4;rx_crc<=crc_byte(rx_crc,rx_data);end
          else if(rx_data=="C")begin magic_count<=1;rx_crc<=crc_byte(32'hffffffff,rx_data);end else magic_count<=0;
        default:magic_count<=0;
       endcase
      end else begin
       req_index<=req_index+1'b1;
       if(req_index<776)rx_crc<=crc_byte(rx_crc,rx_data);
       if(req_index<8)sequence_id[8*(req_index-4)+:8]<=rx_data;
       else if(req_index<776)begin core_in_we<=1;core_in_addr<=req_index-8;core_in_data<=rx_data;end
       else if(req_index<779)received_crc[8*(req_index-776)+:8]<=rx_data;
       else begin
        packet_active<=0;magic_count<=0;
        // 未验证的像素可以写空闲 RAM；只有全部 780 字节及 CRC 有效才启动。
        if({rx_data,received_crc[23:0]}==~rx_crc)begin
         core_start<=1;accepted<=accepted+1'b1;state<=RUN;score_mask<=0;done_seen<=0;
        end else crc_errors<=crc_errors+1'b1;
       end
      end
     end else if(packet_active || magic_count!=0)begin
      if(timeout_count>=RX_TIMEOUT_CYCLES-1)begin
       timeout_count<=0;packet_active<=0;magic_count<=0;rx_errors<=rx_errors+1'b1;
      end else timeout_count<=timeout_count+1'b1;
     end else timeout_count<=0;
    end
    RUN:begin
     if(score_valid && score_index<36)begin scores[score_index]<=score_data;score_mask[score_index]<=1'b1;end
     if(core_done)begin done_seen<=1;result_cycles<=core_cycles;end
     // done 可与最后一项同拍，下一拍检查完整位图，避免漏分数或重复分数误计。
     if(done_seen && (&score_mask))begin state<=SEND;tx_index<=0;tx_crc<=32'hffffffff;end
    end
    SEND:if(tx_ready)begin
     if(tx_index<156)tx_crc<=crc_byte(tx_crc,tx_data);
     if(tx_index==155)response_crc<=~crc_byte(tx_crc,tx_data);
     if(tx_index==159)state<=DRAIN;
     else tx_index<=tx_index+1'b1;
    end
    // 最后一字节真正发完才重开接收；RUN/SEND/DRAIN 期间收到的请求丢弃。
    DRAIN:if(tx_ready)begin state<=RECV;timeout_count<=0;magic_count<=0;packet_active<=0;end
    default:state<=RECV;
   endcase
  end
 end
endmodule
