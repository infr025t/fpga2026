`timescale 1ns/1ps
// 100MHz / 12Mbaud。整帧上传、字符识别与字符分割共用停止等待通道。
module norm_uart_bridge #(
 parameter integer RX_TIMEOUT_CYCLES=10000000,
 parameter integer NORM_TIMEOUT_CYCLES=200000000,
 parameter integer CNN_TIMEOUT_CYCLES=20000000,
 parameter integer SEG_TIMEOUT_CYCLES=200000000)(
 input wire clk,rst,uart_rxd,output wire uart_txd,
 output reg frame_we,output reg[14:0]frame_addr,output reg[7:0]frame_data,
 output reg norm_start,output reg[7:0]box_x,box_y,box_w,box_h,roi_x0,roi_y0,roi_x1,roi_y1,output reg[1:0]flags,
 input wire norm_busy,norm_done,norm_error,input wire[31:0]norm_cycles,
 input wire norm_pixel_we,input wire[9:0]norm_pixel_addr,input wire[7:0]norm_pixel_data,
 output reg core_start,output wire core_in_we,output wire[9:0]core_in_addr,output wire[7:0]core_in_data,
 input wire core_busy,core_done,score_valid,input wire[5:0]score_index,input wire signed[31:0]score_data,input wire[31:0]core_cycles,
 output reg seg_start,input wire seg_busy,seg_done,input wire[7:0]seg_error,input wire[31:0]seg_cycles,
 input wire seg_box_we,input wire[5:0]seg_box_index,input wire[7:0]seg_box_x,seg_box_y,seg_box_w,seg_box_h,input wire[6:0]seg_box_count,
 output reg worker_reset,output reg[31:0]accepted,crc_errors,rx_errors,
 output reg frame_valid,output reg[31:0]frame_id);
 localparam RECV=0,NORMALIZE=1,CLASSIFY=2,SEND=3,DRAIN=4,SEGMENT=5;
 reg[2:0]state;wire rv,re;wire[7:0]rd;
 uart_fast_rx receiver(.clk(clk),.rst(rst),.rx(uart_rxd),.valid(rv),.data(rd),.framing_error(re));
 reg[2:0]magic_count;reg packet_active,frame_packet,ack_packet,segment_packet,segment_response;
 reg[14:0]req_index;reg[31:0]rx_crc,received_crc,sequence_id,requested_frame,timeout_count,watchdog;
 reg[7:0]raw_flags;reg[9:0]pixel_count;reg pixel_bad;
 (* ram_style="distributed" *) reg[7:0]pixels[0:767];
 (* ram_style="distributed" *) reg[31:0]segment_boxes[0:63];
 reg[6:0]segment_received;reg segment_bad;reg[31:0]result_seg_cycles;
 reg signed[31:0]scores[0:35];reg[35:0]score_mask;reg done_seen;
 reg[31:0]status,result_norm_cycles,result_cnn_cycles;
 reg[9:0]tx_index;reg[31:0]tx_crc,response_crc;reg[7:0]tx_data;wire tx_ready;
 wire[14:0]crc_start=frame_packet?15'd19208:(segment_packet?15'd17:15'd21);
 wire[9:0]tx_crc_start=ack_packet?10'd12:(segment_response?10'd276:10'd932);
 uart_fast_tx transmitter(.clk(clk),.rst(rst),.valid(state==SEND),.data(tx_data),.ready(tx_ready),.tx(uart_txd));
 // 正常像素流同时进入CNN输入RAM和回传缓存；非法地址不越界写入。
 assign core_in_we=(state==NORMALIZE)&&norm_pixel_we&&(norm_pixel_addr<768);
 assign core_in_addr=norm_pixel_addr;assign core_in_data=norm_pixel_data;
 function automatic[31:0]crc_byte(input[31:0]c,input[7:0]b);
  reg[31:0]v;integer k;begin v=c^{24'b0,b};for(k=0;k<8;k=k+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;crc_byte=v;end
 endfunction
 always @*begin
  tx_data=0;
  if(tx_index==0)tx_data="N";
  else if(tx_index==1)tx_data=ack_packet?"F":(segment_response?"S":"R");
  else if(tx_index==2)tx_data=ack_packet?"A":(segment_response?"R":"S");
  else if(tx_index==3)tx_data="1";
  else if(tx_index<8)tx_data=sequence_id>>(8*(tx_index-4));
  else if(tx_index<12)tx_data=status>>(8*(tx_index-8));
  else if(tx_index>=tx_crc_start)tx_data=response_crc>>(8*(tx_index-tx_crc_start));
  else if(segment_response)begin
   if(tx_index<16)tx_data=result_seg_cycles>>(8*(tx_index-12));
   else if(tx_index<20)tx_data=(status==0)?({25'd0,segment_received}>>(8*(tx_index-16))):0;
   else if(status==0 && ((tx_index-20)>>2)<segment_received)
    tx_data=segment_boxes[(tx_index-20)>>2]>>(8*tx_index[1:0]);
  end
  else if(tx_index<16)tx_data=result_norm_cycles>>(8*(tx_index-12));
  else if(tx_index<20)tx_data=result_cnn_cycles>>(8*(tx_index-16));
  else if(status==0)begin
   if(tx_index<788)tx_data=pixels[tx_index-20];
   else if(tx_index<932)tx_data=scores[(tx_index-788)>>2]>>(8*tx_index[1:0]);
  end
 end
 always @(posedge clk)begin
  if(rst)begin
   state<=RECV;frame_we<=0;frame_addr<=0;frame_data<=0;norm_start<=0;core_start<=0;seg_start<=0;worker_reset<=0;
   box_x<=0;box_y<=0;box_w<=0;box_h<=0;roi_x0<=0;roi_y0<=0;roi_x1<=0;roi_y1<=0;flags<=0;raw_flags<=0;
   accepted<=0;crc_errors<=0;rx_errors<=0;frame_valid<=0;frame_id<=0;
   magic_count<=0;packet_active<=0;frame_packet<=0;ack_packet<=0;segment_packet<=0;segment_response<=0;req_index<=0;
   rx_crc<=32'hffffffff;received_crc<=0;sequence_id<=0;requested_frame<=0;timeout_count<=0;watchdog<=0;
   pixel_count<=0;pixel_bad<=0;score_mask<=0;done_seen<=0;status<=0;result_norm_cycles<=0;result_cnn_cycles<=0;
   segment_received<=0;segment_bad<=0;result_seg_cycles<=0;
   tx_index<=0;tx_crc<=32'hffffffff;response_crc<=0;
  end else begin
   frame_we<=0;norm_start<=0;core_start<=0;seg_start<=0;worker_reset<=0;
   case(state)
    RECV:begin
     if(norm_busy||core_busy||seg_busy)begin packet_active<=0;magic_count<=0;timeout_count<=0;end
     else if(re)begin rx_errors<=rx_errors+1'b1;packet_active<=0;magic_count<=0;timeout_count<=0;end
     else if(rv)begin
      timeout_count<=0;
      if(!packet_active)begin
       // NFR1/NCH1/NSG1前缀扫描；失配N保留为新前缀。
       if((magic_count==0)||(magic_count==1 && rd!="F" && rd!="C" && rd!="S")||
          (magic_count==2 && rd!=(frame_packet?"R":(segment_packet?"G":"H")))||(magic_count==3 && rd!="1"))begin
        if(rd=="N")begin magic_count<=1;rx_crc<=crc_byte(32'hffffffff,rd);end else magic_count<=0;
       end else begin
        rx_crc<=crc_byte(rx_crc,rd);
        case(magic_count)
         1:begin frame_packet<=(rd=="F");segment_packet<=(rd=="S");magic_count<=2;end
         2:magic_count<=3;
         3:begin packet_active<=1;magic_count<=0;req_index<=4;if(frame_packet)frame_valid<=0;end
         default:magic_count<=0;
        endcase
       end
      end else begin
       req_index<=req_index+1'b1;
       if(req_index<crc_start)rx_crc<=crc_byte(rx_crc,rd);
       if(req_index<8)sequence_id[8*(req_index-4)+:8]<=rd;
       else if(req_index<crc_start)begin
        if(frame_packet)begin frame_we<=1;frame_addr<=req_index-8;frame_data<=rd;end
        else if(segment_packet)case(req_index)
         8,9,10,11:requested_frame[8*(req_index-8)+:8]<=rd;
         12:roi_x0<=rd;13:roi_y0<=rd;14:roi_x1<=rd;15:roi_y1<=rd;
         16:begin raw_flags<=rd;flags<=rd[1:0];end
        endcase
        else case(req_index)
         8,9,10,11:requested_frame[8*(req_index-8)+:8]<=rd;
         12:box_x<=rd;13:box_y<=rd;14:box_w<=rd;15:box_h<=rd;
         16:roi_x0<=rd;17:roi_y0<=rd;18:roi_x1<=rd;19:roi_y1<=rd;
         20:begin raw_flags<=rd;flags<=rd[1:0];end
        endcase
       end else if(req_index<crc_start+3)received_crc[8*(req_index-crc_start)+:8]<=rd;
       else begin
        packet_active<=0;magic_count<=0;
        if({rd,received_crc[23:0]}!=~rx_crc)crc_errors<=crc_errors+1'b1;
        else begin
         accepted<=accepted+1'b1;status<=0;result_norm_cycles<=0;result_cnn_cycles<=0;result_seg_cycles<=0;segment_received<=0;segment_bad<=0;
         tx_index<=0;tx_crc<=32'hffffffff;ack_packet<=frame_packet;segment_response<=segment_packet;
         if(frame_packet)begin frame_valid<=1;frame_id<=sequence_id;state<=SEND;end
         else if(!frame_valid || requested_frame!=frame_id)begin status<=1;state<=SEND;end
         else if(raw_flags>3)begin status<=2;state<=SEND;end
         else if(segment_packet)begin seg_start<=1;watchdog<=0;state<=SEGMENT;end
         else begin norm_start<=1;pixel_count<=0;pixel_bad<=0;watchdog<=0;state<=NORMALIZE;end
        end
       end
      end
     end else if(packet_active||magic_count!=0)begin
      if(timeout_count>=RX_TIMEOUT_CYCLES-1)begin timeout_count<=0;packet_active<=0;magic_count<=0;rx_errors<=rx_errors+1'b1;end
      else timeout_count<=timeout_count+1'b1;
     end else timeout_count<=0;
    end
    NORMALIZE:begin
     watchdog<=watchdog+1'b1;
     if(norm_pixel_we)begin
      if(norm_pixel_addr<768)pixels[norm_pixel_addr]<=norm_pixel_data;
      if(pixel_count>=768 || norm_pixel_addr!=pixel_count)pixel_bad<=1;
      if(pixel_count<769)pixel_count<=pixel_count+1'b1;
     end
     if(norm_done)begin
      result_norm_cycles<=norm_cycles;
      if(norm_error || pixel_bad || pixel_count!=768 || norm_pixel_we)begin status<=2;state<=SEND;end
      else begin core_start<=1;watchdog<=0;score_mask<=0;done_seen<=0;state<=CLASSIFY;end
     end else if(watchdog>=NORM_TIMEOUT_CYCLES-1)begin
      status<=3;state<=SEND;worker_reset<=1;frame_valid<=0;result_norm_cycles<=norm_cycles;
     end
    end
    CLASSIFY:begin
     watchdog<=watchdog+1'b1;
     if(score_valid && score_index<36)begin scores[score_index]<=score_data;score_mask[score_index]<=1'b1;end
     if(core_done)begin done_seen<=1;result_cnn_cycles<=core_cycles;end
     // 最后一分数与done同拍安全；下一拍完整位图再发送。
     if(done_seen && (&score_mask))state<=SEND;
     else if(watchdog>=CNN_TIMEOUT_CYCLES-1)begin status<=3;state<=SEND;worker_reset<=1;frame_valid<=0;result_cnn_cycles<=core_cycles;end
    end
    SEGMENT:begin
     watchdog<=watchdog+1'b1;
     if(seg_box_we)begin
      if(segment_received>=64 || {1'b0,seg_box_index}!=segment_received)segment_bad<=1;
      else begin
       segment_boxes[seg_box_index]<={seg_box_h,seg_box_w,seg_box_y,seg_box_x};
       segment_received<=segment_received+1'b1;
      end
     end
     // The producer must assert done at least one cycle after its last box.
     if(seg_done)begin
      result_seg_cycles<=seg_cycles;state<=SEND;
      if(seg_error==1)status<=2;
      else if(seg_error!=0 || segment_bad || seg_box_we || seg_box_count>64 || seg_box_count!=segment_received)status<=4;
     end else if(watchdog>=SEG_TIMEOUT_CYCLES-1)begin
      status<=3;state<=SEND;worker_reset<=1;frame_valid<=0;result_seg_cycles<=seg_cycles;
     end
    end
    SEND:if(tx_ready)begin
     if(tx_index<tx_crc_start)tx_crc<=crc_byte(tx_crc,tx_data);
     if(tx_index==tx_crc_start-1)response_crc<=~crc_byte(tx_crc,tx_data);
     if(tx_index==tx_crc_start+3)state<=DRAIN;else tx_index<=tx_index+1'b1;
    end
    DRAIN:if(tx_ready)begin state<=RECV;timeout_count<=0;magic_count<=0;packet_active<=0;end
    default:state<=RECV;
   endcase
  end
 end
endmodule
