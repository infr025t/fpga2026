`timescale 1ns/1ps
// 固定 100 MHz / 12 Mbaud / 8N1。3/25 分数累加器保留余数，避免逐位误差累积。
module uart_fast_rx(input wire clk,rst,rx,output reg valid,output reg [7:0]data,output reg framing_error);
 (* ASYNC_REG="TRUE" *) reg rx_meta=1'b1,rx_sync=1'b1;
 reg [1:0] state;
 localparam IDLE=2'd0,START=2'd1,BITS=2'd2,RECOVER=2'd3;
 reg [4:0] phase;
 reg [3:0] bit_index;
 reg [7:0] shift;
 always @(posedge clk)begin
  if(rst)begin rx_meta<=1'b1;rx_sync<=1'b1;end
  else begin rx_meta<=rx;rx_sync<=rx_meta;end
 end
 always @(posedge clk)begin
  if(rst)begin state<=IDLE;phase<=0;bit_index<=0;shift<=0;data<=0;valid<=0;framing_error<=0;end
  else begin
   valid<=0;framing_error<=0;
   case(state)
    IDLE:if(!rx_sync)begin
     state<=START;
     // 同步器到状态机约 2~3 拍；补偿后在起始位中心附近确认低电平。
     // 后续中心采样每 25/3 拍一次，最早/最晚采样均在有效位内部。
     phase<=20;
    end
    START,BITS:begin
     if(phase>=22)begin
      phase<=phase-22;
      if(state==START)begin
       if(rx_sync)state<=IDLE;
       else begin state<=BITS;bit_index<=0;end
      end
      else if(bit_index<8)begin shift[bit_index]<=rx_sync;bit_index<=bit_index+1'b1;end
      else if(rx_sync)begin data<=shift;valid<=1;state<=IDLE;end
      else begin framing_error<=1;state<=RECOVER;end
     end
     else phase<=phase+3;
    end
    // 错 stop 后必须先见高电平，连续低电平只记一次错误。
    RECOVER:if(rx_sync)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
