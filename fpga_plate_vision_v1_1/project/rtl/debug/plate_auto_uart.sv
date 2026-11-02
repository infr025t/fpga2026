`timescale 1ns/1ps
// 旁路遥测：任何拥塞只丢观测包，不向计算/采集端输出ready。
module plate_auto_uart #(parameter DYNAMIC_ROI=0,PREFIX_FILTER=0,SPLIT_TOUCHING=0)(
 input wire clk,rst,
 input wire cap_begin,cap_end,cap_abort,
 input wire [31:0] frame_id,capture_tick,raw_crc,
 input wire [7:0] roi_x0,roi_y0,roi_x1,roi_y1,input wire [1:0] flags,
 input wire frame_we,input wire [14:0] frame_addr,input wire [7:0] frame_data,
 input wire seg_event,input wire [2047:0] boxes_flat,input wire [6:0] box_count,
 input wire [7:0] seg_status,input wire [31:0] seg_elapsed,
 input wire [7:0] seg_roi_x0,seg_roi_y0,seg_roi_x1,seg_roi_y1,
 input wire char_begin,input wire [5:0] char_index,input wire [31:0] char_box,
 input wire norm_pixel_we,input wire [9:0] norm_pixel_addr,input wire [7:0] norm_pixel_data,
 input wire norm_done,input wire [31:0] norm_cycles,
 input wire score_valid,input wire [5:0] score_index,input wire signed [31:0] score_data,
 input wire char_event,input wire [5:0] best_index,input wire [7:0] best_ascii,
 input wire [31:0] norm_elapsed,core_elapsed,
 input wire result_event,input wire [7:0] result_status,input wire [6:0] completed_chars,
 input wire [511:0] text_flat,input wire [31:0] elapsed_cycles,bad_captures,skipped_frames,
 output wire uart_txd,output reg [31:0] dropped,packets
);
 localparam IDLE=0,FRAME=1,SEG=2,CHAR=3,RESULT=4;
 reg [2:0] kind;
 reg [14:0] pos;
 reg [31:0] packet_frame,crc;
 (* ram_style="distributed" *) reg [7:0] fifo[0:2047];
 reg [10:0] wrptr,rdptr; reg [11:0] used;
 wire tx_ready; wire pop=(used!=0)&&tx_ready;
 uart_fast_tx tx(.clk(clk),.rst(rst),.valid(used!=0),.data(fifo[rdptr]),.ready(tx_ready),.tx(uart_txd));
 // 只吸收20字节包头期间的原始像素，绝不是整帧缓存。
 reg [7:0] raw_pending[0:7];reg [2:0] raw_wp,raw_rp;reg [3:0] raw_used;
 reg [14:0] raw_seen;reg cap_ok;reg [31:0] cap_crc,cap_tick,cap_roi;reg [1:0] cap_flags;
 reg seg_pending,char_pending,result_pending;
 reg [31:0] sg_frame,sg_cycles,sg_roi;reg [7:0] sg_status;reg [6:0] sg_count;reg [2047:0] sg_boxes;
 localparam SEG_BOX_START=DYNAMIC_ROI?24:20,SEG_BODY_LEN=DYNAMIC_ROI?280:276;
 reg [31:0] ch_frame,ch_box;reg [5:0] ch_index;
 reg [31:0] active_box;reg [5:0] active_index;reg [9:0] norm_seen;
 reg norm_ok,char_ok;reg [31:0] norm_time,core_time;reg [5:0] class_id;reg [7:0] ascii_code;
 reg [31:0] scores[0:35];reg [35:0] score_seen;
 reg [31:0] rs_frame,rs_cycles,rs_bad,rs_skip,rs_drop;reg [7:0] rs_status;
 reg [6:0] rs_count;reg [511:0] rs_text;
 reg emit;reg [7:0] outbyte;reg [14:0] body_len;reg fault;
 // 时序切分：宽元数据选字节只到本级寄存器，下一拍才做CRC和FIFO写入。
 // 包头/包尾标记与字节同行；CRC在首字节真正入队时初始化，避免提前清掉上一包尾CRC。
 reg stage_valid,stage_first,stage_footer,stage_last;
 reg [7:0] stage_byte;reg [1:0] stage_crc_index;
 wire raw_push=frame_we&&(kind==FRAME);
 wire raw_pop=emit&&(kind==FRAME)&&(pos>=20)&&(pos<19220);
 // 写端仅依赖已寄存valid和容量，不能把本拍复杂的事件/位置故障译码接回FIFO写使能。
 // 本拍故障清除下一拍valid；上一拍已接纳字节仍可作为不完整前缀提交。
 // stage_last仅在整包已选完后出现，此时上游已退出该包；其提交仍是完整包。
 wire push=stage_valid && (used<2048 || pop);
 // 已进入寄存级的字节占一个FIFO预留槽；同拍UART读取可以释放一个槽。
 wire reserve_full=(used==2048 && (stage_valid || !pop)) || (used==2047 && stage_valid && !pop);
 wire [7:0] fifo_byte=stage_footer?byte32(~crc,{30'd0,stage_crc_index}):stage_byte;
 integer k;integer slot;reg [31:0] word_value;
 function automatic [31:0] crc_byte(input [31:0] c,input [7:0] b);
 reg [31:0] v;integer j;begin v=c^b;for(j=0;j<8;j=j+1)v=(v>>1)^(v[0]?32'hedb88320:0);crc_byte=v;end endfunction
 function automatic [7:0] byte32(input [31:0] v,input integer index);begin byte32=v>>(8*index);end endfunction
 always @* begin
  emit=0;outbyte=0;body_len=0;word_value=0;slot=0;
  case(kind)
   FRAME:begin
    body_len=19224;
    if(pos<20)begin
     emit=1;
     if(pos<4)outbyte=byte32(32'h31464941,pos);
     else if(pos<8)outbyte=byte32(packet_frame,pos-4);
     else if(pos<12)outbyte=byte32(cap_tick,pos-8);
     else if(pos<16)outbyte=byte32(cap_roi,pos-12);
     else if(pos==16)outbyte={6'b0,cap_flags};
    end else if(pos<19220)begin emit=(raw_used!=0);outbyte=raw_pending[raw_rp];end
    else if(pos<19224)begin emit=cap_ok;outbyte=byte32(cap_crc,pos-19220);end
   end
   SEG:begin
    body_len=SEG_BODY_LEN;emit=1;
    // ASG4=动态ROI+前缀过滤+粘连拆分；ASG5仅拆分。保持旧记录按旧规则核验。
    if(pos<4)outbyte=byte32(DYNAMIC_ROI?(SPLIT_TOUCHING?(PREFIX_FILTER?32'h34475341:32'h35475341):(PREFIX_FILTER?32'h33475341:32'h32475341)):32'h31475341,pos);
    else if(pos<8)outbyte=byte32(packet_frame,pos-4);
    else if(pos<12)outbyte=byte32({24'b0,sg_status},pos-8);
    else if(pos<16)outbyte=byte32(sg_cycles,pos-12);
    else if(pos<20)outbyte=byte32({25'b0,sg_count},pos-16);
    else if(DYNAMIC_ROI && pos<24)outbyte=byte32(sg_roi,pos-20);
    else if(pos<SEG_BODY_LEN)begin
     slot=(pos-SEG_BOX_START)>>2;
     if(slot<sg_count)outbyte=sg_boxes[(pos-SEG_BOX_START)*8+:8];
    end
   end
   CHAR:begin
    body_len=940;
    if(pos<16)begin
     emit=1;
     if(pos<4)outbyte=byte32(32'h32524341,pos);
     else if(pos<8)outbyte=byte32(packet_frame,pos-4);
     else if(pos<12)outbyte=byte32({26'b0,active_index},pos-8);
     else outbyte=byte32(active_box,pos-12);
    end else if(pos<784)begin emit=norm_pixel_we;outbyte=norm_pixel_data;end
    else if(pos<788)begin emit=norm_ok;outbyte=byte32(norm_time,pos-784);end
    else if(pos<932)begin slot=(pos-788)>>2;emit=score_seen[slot];outbyte=byte32(scores[slot],(pos-788)%4);end
    else if(pos<940)begin
     emit=char_ok;
     if(pos<936)outbyte=byte32(core_time,pos-932);
     else if(pos==936)outbyte={2'b0,class_id};
     else if(pos==937)outbyte=ascii_code;
    end
   end
   RESULT:begin
    body_len=96;emit=1;
    if(pos<4)outbyte=byte32(32'h31524541,pos);
    else if(pos<8)outbyte=byte32(packet_frame,pos-4);
    else if(pos<12)outbyte=byte32({24'b0,rs_status},pos-8);
    else if(pos<16)outbyte=byte32({25'b0,rs_count},pos-12);
    else if(pos<20)outbyte=byte32(rs_cycles,pos-16);
    else if(pos<24)outbyte=byte32(rs_bad,pos-20);
    else if(pos<28)outbyte=byte32(rs_skip,pos-24);
    else if(pos<32)outbyte=byte32(rs_drop,pos-28);
    else if(pos<96 && pos-32<rs_count)outbyte=rs_text[(pos-32)*8+:8];
   end
   default:begin end
  endcase
  // 本级只传递CRC字节序号；CRC值由下一拍取得，包含最后一个正文字节。
  if(kind!=IDLE && pos>=body_len)begin emit=1;outbyte=0;end
  fault=0;
  if((emit && reserve_full) || (stage_valid && used==2048 && !pop))fault=1;
  if(cap_begin && (kind!=IDLE || seg_pending || char_pending || result_pending))fault=1;
  if(seg_event && (seg_pending || kind==SEG || box_count>64))fault=1;
  if(char_begin && char_pending)fault=1;
  if(result_event && (result_pending || kind==RESULT || completed_chars>64))fault=1;
  // worker超时/错误提前发结果时，中止没有尾部的字符包并保留错误结果。
  if(result_event && kind==CHAR && !char_ok && !char_event)fault=1;
  if(kind==FRAME)begin
   if(cap_abort)fault=1;
   if(frame_we && (frame_addr!=raw_seen || raw_seen>=19200 || (raw_used==8&&!raw_pop)))fault=1;
   if(cap_end && raw_seen+{14'b0,frame_we}!=19200)fault=1;
  end
  if(norm_pixel_we && (kind==CHAR || char_pending))begin
   if(kind!=CHAR || pos<16 || pos>=784 || norm_pixel_addr!=norm_seen || norm_seen>=768)fault=1;
  end
  if(kind==CHAR)begin
   if(norm_done && norm_seen+{9'b0,norm_pixel_we}!=768)fault=1;
   if(score_valid && (score_index>=36 || score_seen[score_index]))fault=1;
   if(char_event && (score_seen!=36'hfffffffff || !norm_ok || best_index>=36 || norm_elapsed!=norm_time))fault=1;
  end
 end
 always @(posedge clk)begin
  if(rst)begin
   kind<=IDLE;pos<=0;crc<=32'hffffffff;packet_frame<=0;
   stage_valid<=0;stage_first<=0;stage_footer<=0;stage_last<=0;stage_byte<=0;stage_crc_index<=0;
   wrptr<=0;rdptr<=0;used<=0;dropped<=0;packets<=0;
   raw_wp<=0;raw_rp<=0;raw_used<=0;raw_seen<=0;cap_ok<=0;
   cap_crc<=0;cap_tick<=0;cap_roi<=0;cap_flags<=0;
   seg_pending<=0;char_pending<=0;result_pending<=0;
   sg_frame<=0;sg_cycles<=0;sg_status<=0;sg_count<=0;sg_boxes<=0;sg_roi<=0;
   ch_frame<=0;ch_box<=0;ch_index<=0;active_box<=0;active_index<=0;norm_seen<=0;
   norm_ok<=0;char_ok<=0;norm_time<=0;core_time<=0;class_id<=0;ascii_code<=0;score_seen<=0;
   rs_frame<=0;rs_cycles<=0;rs_bad<=0;rs_skip<=0;rs_drop<=0;rs_status<=0;rs_count<=0;rs_text<=0;
  end else begin
   if(pop)rdptr<=rdptr+1'b1;
   stage_valid<=0;
   if(push)begin
    fifo[wrptr]<=fifo_byte;wrptr<=wrptr+1'b1;
    if(!stage_footer)crc<=crc_byte(stage_first?32'hffffffff:crc,stage_byte);
    if(stage_last)packets<=packets+1'b1;
   end
   case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:begin end endcase
   if(fault)begin
    // 已发送的前缀保留，末尾CRC不再发送；PC通过下一个完整CRC包重新同步。
    kind<=IDLE;pos<=0;seg_pending<=0;char_pending<=0;result_pending<=0;
    raw_used<=0;raw_wp<=0;raw_rp<=0;cap_ok<=0;norm_ok<=0;char_ok<=0;score_seen<=0;dropped<=dropped+1'b1;
    if(result_event && !result_pending && kind!=RESULT && completed_chars<=64)begin
     result_pending<=1;rs_frame<=frame_id;rs_status<=result_status;rs_count<=completed_chars;
     rs_cycles<=elapsed_cycles;rs_bad<=bad_captures;rs_skip<=skipped_frames;rs_drop<=dropped+1'b1;rs_text<=text_flat;
    end
   end else begin
    stage_valid<=emit;
    if(emit)begin
     stage_byte<=outbyte;stage_first<=(pos==0);stage_footer<=(pos>=body_len);
     stage_crc_index<=pos[1:0];stage_last<=(pos==body_len+3);
    end
    if(seg_event)begin
     sg_roi<={seg_roi_y1,seg_roi_x1,seg_roi_y0,seg_roi_x0};
     seg_pending<=1;sg_frame<=frame_id;sg_cycles<=seg_elapsed;sg_status<=seg_status;sg_count<=box_count;sg_boxes<=boxes_flat;
    end
    if(char_begin)begin char_pending<=1;ch_frame<=frame_id;ch_box<=char_box;ch_index<=char_index;end
    if(result_event)begin
     result_pending<=1;rs_frame<=frame_id;rs_status<=result_status;rs_count<=completed_chars;
     rs_cycles<=elapsed_cycles;rs_bad<=bad_captures;rs_skip<=skipped_frames;rs_drop<=dropped;rs_text<=text_flat;
    end
    if(kind==IDLE)begin
     pos<=0;
     if(cap_begin)begin
      kind<=FRAME;packet_frame<=frame_id;cap_tick<=capture_tick;cap_roi<={roi_y1,roi_x1,roi_y0,roi_x0};cap_flags<=flags;
      raw_seen<=0;raw_used<=0;raw_wp<=0;raw_rp<=0;cap_ok<=0;
     end else if(seg_pending)begin kind<=SEG;packet_frame<=sg_frame;seg_pending<=0;end
     else if(char_pending)begin
      kind<=CHAR;packet_frame<=ch_frame;active_box<=ch_box;active_index<=ch_index;char_pending<=0;
      norm_seen<=0;norm_ok<=0;char_ok<=0;score_seen<=0;
     end else if(result_pending)begin kind<=RESULT;packet_frame<=rs_frame;result_pending<=0;end
    end
    if(kind==FRAME)begin
     if(raw_push)begin raw_pending[raw_wp]<=frame_data;raw_wp<=raw_wp+1'b1;raw_seen<=raw_seen+1'b1;end
     if(raw_pop)raw_rp<=raw_rp+1'b1;
     case({raw_push,raw_pop})2'b10:raw_used<=raw_used+1'b1;2'b01:raw_used<=raw_used-1'b1;default:begin end endcase
     if(cap_end)begin cap_ok<=1;cap_crc<=raw_crc;end
    end
    if(kind==CHAR)begin
     if(norm_pixel_we)norm_seen<=norm_seen+1'b1;
     if(norm_done)begin norm_ok<=1;norm_time<=norm_cycles;end
     if(score_valid && score_index<36)begin scores[score_index]<=score_data;score_seen[score_index]<=1;end
     if(char_event)begin char_ok<=1;core_time<=core_elapsed;class_id<=best_index;ascii_code<=best_ascii;end
    end
    if(emit)begin
     if(pos==body_len+3)begin kind<=IDLE;pos<=0;end
     else pos<=pos+1'b1;
    end
   end
  end
 end
endmodule
