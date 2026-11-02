`timescale 1ns/1ps
// 显示实际定位ROI：160x120坐标映射为640x480，不添加图像RAM或处理反压。
// 新框/无框结果先暂存，视频帧开始时统一提交，防止一帧内框位置跳变。
module plate_roi_overlay(
 input wire clk,rst,enabled,frame_start,roi_event,roi_valid,
 input wire[7:0]roi_x0,roi_y0,roi_x1,roi_y1,
 input wire[9:0]x,input wire[8:0]y,output wire border
);
 reg pending_valid,active_valid;
 reg[9:0]pending_left,pending_right,active_left,active_right;
 reg[8:0]pending_top,pending_bottom,active_top,active_bottom;
 wire bounds_valid=roi_x0<roi_x1 && roi_x1<=160 && roi_y0<roi_y1 && roi_y1<=120;
 always @(posedge clk)begin
  if(rst)begin
   pending_valid<=0;active_valid<=0;
   pending_left<=0;pending_right<=0;pending_top<=0;pending_bottom<=0;
   active_left<=0;active_right<=0;active_top<=0;active_bottom<=0;
  end else begin
   if(!enabled)pending_valid<=0;
   else if(roi_event)begin
    pending_valid<=roi_valid&&bounds_valid;
    pending_left<={roi_x0,2'b00};pending_right<={roi_x1,2'b00};
    pending_top<={roi_y0[6:0],2'b00};pending_bottom<={roi_y1[6:0],2'b00};
   end
   if(frame_start)begin
    active_valid<=enabled&&pending_valid;
    active_left<=pending_left;active_right<=pending_right;
    active_top<=pending_top;active_bottom<=pending_bottom;
   end
  end
 end
 // 半开区间[x0,x1)、[y0,y1)，框线在区域内部宽2像素；画面居中偏移由LCD窗口负责。
 assign border=active_valid && x>=active_left && x<active_right && y>=active_top && y<active_bottom &&
  (x<active_left+10'd2 || x>=active_right-10'd2 || y<active_top+9'd2 || y>=active_bottom-9'd2);
endmodule
