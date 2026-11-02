`timescale 1ns/1ps
// 定位与原分割器串行共享RAM读口；人工回放仍按上传ROI执行，不改变原数学算法。
module plate_segment_frontend #(parameter AUTO_LOCATE=0,SKIP_CHINESE=0,SPLIT_TOUCHING=0)(
 input wire clk,rst,start,locate_enable,
 input wire[7:0]roi_x0,roi_y0,roi_x1,roi_y1,input wire[1:0]flags,
 output wire busy,done,output wire[7:0]error,output wire[31:0]cycles,
 output wire[14:0]frame_read_addr,input wire[7:0]frame_read_data,
 output wire box_we,output wire[5:0]box_index,output wire[7:0]box_x,box_y,box_w,box_h,
 output wire[6:0]box_count,output wire[7:0]selected_x0,selected_y0,selected_x1,selected_y1
);
 generate if(!AUTO_LOCATE)begin:fixed_region
  assign selected_x0=roi_x0;assign selected_y0=roi_y0;assign selected_x1=roi_x1;assign selected_y1=roi_y1;
  char_segmenter segmenter(.clk(clk),.rst(rst),.start(start),.skip_prefix(1'b0),.split_touching(1'b0),.roi_x0(roi_x0),.roi_y0(roi_y0),.roi_x1(roi_x1),.roi_y1(roi_y1),.flags(flags),
   .busy(busy),.done(done),.error(error),.cycles(cycles),.frame_read_addr(frame_read_addr),.frame_read_data(frame_read_data),
   .box_we(box_we),.box_index(box_index),.box_x(box_x),.box_y(box_y),.box_w(box_w),.box_h(box_h),.box_count(box_count));
 end else begin:dynamic_region
  localparam IDLE=0,LOCATE=1,LAUNCH=2,SEGMENT=3,FINISH=4;
  reg[2:0]state;reg loc_start,seg_start,active,complete;reg[7:0]status,rx0,ry0,rx1,ry1;
  reg[1:0]mode;reg[31:0]elapsed;reg[6:0]count;reg active_locate;
  wire ld,lf,sd;wire[7:0]lx0,ly0,lx1,ly1,se;wire[14:0]la,sa;wire[6:0]scount;wire swe;
  assign busy=active;assign done=complete;assign error=status;assign cycles=elapsed;assign box_count=count;
  assign selected_x0=rx0;assign selected_y0=ry0;assign selected_x1=rx1;assign selected_y1=ry1;
  assign frame_read_addr=(state==LOCATE)?la:sa;assign box_we=swe&&(state==SEGMENT);
  plate_region_locator locator(.clk(clk),.rst(rst),.start(loc_start),.busy(),.done(ld),.found(lf),
   .x0(lx0),.y0(ly0),.x1(lx1),.y1(ly1),.cycles(),.read_addr(la),.read_data(frame_read_data));
  char_segmenter #(.ENABLE_PREFIX(SKIP_CHINESE),.ENABLE_SPLIT(SPLIT_TOUCHING)) segmenter(.clk(clk),.rst(rst),.start(seg_start),.skip_prefix(active_locate),.split_touching(active_locate),.roi_x0(rx0),.roi_y0(ry0),.roi_x1(rx1),.roi_y1(ry1),.flags(mode),
   .busy(),.done(sd),.error(se),.cycles(),.frame_read_addr(sa),.frame_read_data(frame_read_data),
   .box_we(swe),.box_index(box_index),.box_x(box_x),.box_y(box_y),.box_w(box_w),.box_h(box_h),.box_count(scount));
  always @(posedge clk)begin
   if(rst)begin state<=IDLE;loc_start<=0;seg_start<=0;active<=0;complete<=0;status<=0;elapsed<=0;count<=0;rx0<=0;ry0<=0;rx1<=0;ry1<=0;mode<=0;active_locate<=0;end
   else begin
    loc_start<=0;seg_start<=0;complete<=0;if(active)elapsed<=elapsed+1'b1;
    case(state)
     IDLE:if(start)begin
      active<=1;status<=0;elapsed<=0;count<=0;mode<=flags;
      active_locate<=locate_enable;
      if(locate_enable)begin rx0<=0;ry0<=0;rx1<=0;ry1<=0;loc_start<=1;state<=LOCATE;end
      else begin rx0<=roi_x0;ry0<=roi_y0;rx1<=roi_x1;ry1<=roi_y1;state<=LAUNCH;end
     end
     LOCATE:if(ld)begin
      if(lf)begin rx0<=lx0;ry0<=ly0;rx1<=lx1;ry1<=ly1;state<=LAUNCH;end
      else state<=FINISH;
     end
     LAUNCH:begin seg_start<=1;state<=SEGMENT;end
     SEGMENT:if(sd)begin count<=scount;status<=se;state<=FINISH;end
     FINISH:begin active<=0;complete<=1;state<=IDLE;end
     default:begin active<=0;status<=8'h04;state<=IDLE;end
    endcase
   end
  end
 end endgenerate
endmodule
