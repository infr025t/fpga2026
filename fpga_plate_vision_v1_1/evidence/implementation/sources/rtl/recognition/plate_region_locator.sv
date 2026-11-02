`timescale 1ns/1ps
// 亮底暗字、近水平单牌面的几何定位。两次扫描原小图RAM，不增帧缓存。
// 用牌面行带和亮跨度替代固定坐标，修复目标平移后被固定ROI截断的问题。
module plate_region_locator(
 input wire clk,rst,start,output reg busy,done,found,
 output reg[7:0]x0,y0,x1,y1,output reg[31:0]cycles,
 output reg[14:0]read_addr,input wire[7:0]read_data
);
 localparam IDLE=0,ISSUE=1,WAIT_RAM=2,TAKE=3,ROW_END=4,BAND_END=5,NEXT_ROW=6,FINISH=7;
 reg[2:0]state;reg second_pass;reg[7:0]low,high,threshold,px,py;
 wire[7:0]next_low=read_data<low?read_data:low,next_high=read_data>high?read_data:high;
 wire[8:0]range_sum={1'b0,next_low}+{1'b0,next_high};
 reg[7:0]row_count,run_left,row_left,row_right,row_width;
 reg[1:0]gap;reg run_active;
 wire[7:0]span=(!run_active||gap==3)?8'd1:px-run_left+8'd1;
 reg band_active;reg[7:0]band_top,band_end,band_peak,band_left,band_right,band_width;
 reg[14:0]band_score,best_score;
 wire[7:0]band_height=band_end-band_top;
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;busy<=0;done<=0;found<=0;x0<=0;y0<=0;x1<=0;y1<=0;cycles<=0;read_addr<=0;
   second_pass<=0;low<=255;high<=0;threshold<=0;px<=0;py<=0;
   row_count<=0;run_left<=0;row_left<=0;row_right<=0;row_width<=0;gap<=3;run_active<=0;
   band_active<=0;band_top<=0;band_end<=0;band_peak<=0;band_left<=0;band_right<=0;band_width<=0;
   band_score<=0;best_score<=0;
  end else begin
   done<=0;if(busy)cycles<=cycles+1'b1;
   case(state)
    IDLE:if(start)begin
     busy<=1;found<=0;x0<=0;y0<=0;x1<=0;y1<=0;cycles<=0;read_addr<=0;low<=255;high<=0;
     second_pass<=0;px<=0;py<=0;row_count<=0;run_active<=0;row_width<=0;gap<=3;
     band_active<=0;band_score<=0;best_score<=0;state<=ISSUE;
    end
    ISSUE:state<=WAIT_RAM;
    WAIT_RAM:state<=TAKE;
    TAKE:begin
     if(!second_pass)begin
      low<=next_low;high<=next_high;
      if(read_addr==19199)begin
       threshold<=range_sum[8:1];read_addr<=0;second_pass<=1;
       state<=(next_high-next_low<32)?FINISH:ISSUE;
      end else begin read_addr<=read_addr+1'b1;state<=ISSUE;end
     end else begin
      if(read_data>threshold)begin
       row_count<=row_count+1'b1;
       if(!run_active||gap==3)run_left<=px;
       run_active<=1;gap<=0;
       if(span>row_width)begin row_width<=span;row_left<=(!run_active||gap==3)?px:run_left;row_right<=px+1'b1;end
      end else if(gap!=3)gap<=gap+1'b1;
      if(px==159)state<=ROW_END;
      else begin px<=px+1'b1;read_addr<=read_addr+1'b1;state<=ISSUE;end
     end
    end
    ROW_END:begin
     if(row_count>=40)begin
      if(!band_active)begin
       band_active<=1;band_top<=py;band_score<={7'd0,row_count};band_peak<=row_count;
       band_left<=row_left;band_right<=row_right;band_width<=row_width;
      end else begin
       band_score<=band_score+{7'd0,row_count};
       if(row_count>band_peak)begin band_peak<=row_count;band_left<=row_left;band_right<=row_right;band_width<=row_width;end
      end
      if(py==119)begin band_end<=120;state<=BAND_END;end else state<=NEXT_ROW;
     end else if(band_active)begin band_end<=py;state<=BAND_END;end
     else state<=(py==119)?FINISH:NEXT_ROW;
    end
    BAND_END:begin
     // 图像边缘截断、过高或过窄的区域不当作完整牌面。
     if(band_top>0&&band_end<120&&band_height>=12&&band_height<=60&&
        band_left>0&&band_right<160&&band_width>=64&&{1'b0,band_width}>={band_height,1'b0}&&band_score>best_score)begin
      found<=1;best_score<=band_score;
      x0<=band_left;y0<=band_top>=3?band_top-8'd3:8'd0;x1<=band_right-1'b1;y1<=band_end-1'b1;
     end
     band_active<=0;state<=(py==119)?FINISH:NEXT_ROW;
    end
    NEXT_ROW:begin
     py<=py+1'b1;px<=0;read_addr<=read_addr+1'b1;
     row_count<=0;run_active<=0;row_width<=0;row_left<=0;row_right<=0;gap<=3;state<=ISSUE;
    end
    FINISH:begin busy<=0;done<=1;state<=IDLE;end
    default:begin busy<=0;found<=0;state<=IDLE;end
   endcase
  end
 end
endmodule
