`timescale 1ns/1ps
// A continuous write epoch spans multiple complete sensor fields.
// RRST is asserted only before the first read or after explicit stop/fault.
module camera_fifo_video #(
 parameter W=640,H=480,FIFO_BYTES=393216,HEAD_ROWS=32,PERIOD=6,
 parameter SAMPLE_PHASE=0,Y_BYTE=0,HREF_MIN=128,HREF_QUALIFY_CYCLES=64,READ_GUARD=129,TIMEOUT=200000000
)(
 input wire clk,rst,start,pause,vsync,href,input wire[7:0]data,
 output reg rclk,rrst,wrst,wen,busy,done,output reg[7:0]error,
 output reg pixel_valid,output reg[7:0]pixel,output reg[7:0]pixel_other,output reg[9:0]pixel_x,output reg[8:0]pixel_y,
 output wire[255:0]debug_timing,output wire[127:0]debug_sync,
 output reg[31:0]sensor_frames,read_frames,sensor_period,max_occupancy);
 localparam N=2*W*H,LINE=2*W;
 localparam STOP=0,PRIME_BLANK=1,PRIME_WAIT=2,PRIME_ROW=3,WAIT_BLANK=4,WAIT_START=5,RUN=6,FAULT=7;
 localparam RI=0,WAIT_HEAD=1,READ_RESET=2,ARM=3,READ=4,DRAIN=5;
 reg[2:0]ws,rs,resets;reg[7:0]phase;
 (* ASYNC_REG="TRUE" *)reg[1:0]vs,hs;
 reg vp,hp,chp,initialized,cycle_active,field_open;
 reg[31:0]raw_high,counted_high,rows,w_total,r_total,index,timer,period_counter;
 reg[31:0]min_href,max_href,last_rows,last_read_bytes,read_at_frame_end;
 reg[9:0]next_x;reg[8:0]next_y;
 wire frame_sync,counted_href;
 wire[31:0]last_long,rejected,max_rejected,last_low;
 vsync_low_filter #(.MIN_LOW(64)) vf(.clk(clk),.rst(rst),.clear_stats(1'b0),.sync_in(vs[1]),
 .sync_out(frame_sync),.last_long_low(last_long),.rejected(rejected),.max_rejected(max_rejected),.last_raw_low(last_low));
 href_stable_filter #(.STABLE_CYCLES(HREF_QUALIFY_CYCLES)) hf(.clk(clk),.rst(rst),.sync_in(hs[1]),.sync_out(counted_href));
 wire rise=frame_sync&&!vp,fall=!frame_sync&&vp,raw_fall=hp&&!hs[1];
 wire row=chp&&!counted_href&&counted_high>=HREF_MIN;
 // Unsigned modular distance remains valid across32-bit counter wrap.
 wire[31:0]available=w_total-r_total;
 wire credit=available>=READ_GUARD;
 wire sample_enable=rs==READ&&cycle_active&&phase==SAMPLE_PHASE&&error==0;
 wire prefetch_enable=ws==RUN && rs==READ_RESET && phase==0 && resets==4;
 (* IOB="TRUE" *)reg[7:0]io_sample;
 reg sample_pending,sample_odd,sample_last;reg[7:0]preceding_byte;
 assign debug_timing={read_frames,max_occupancy,max_href,min_href,read_at_frame_end,sensor_period,last_read_bytes,last_rows};
 assign debug_sync={32'd0,max_rejected,rejected,last_long};
 initial if(SAMPLE_PHASE<0 || SAMPLE_PHASE>=PERIOD || PERIOD<6 || PERIOD>255 || HEAD_ROWS*LINE<READ_GUARD || HEAD_ROWS*LINE>=FIFO_BYTES)$fatal(1,"unsafe video FIFO parameters");
 always @(posedge clk)begin
  if(sample_enable || prefetch_enable)io_sample<=data;
 end
 always @(posedge clk)begin
  pixel_valid<=0;done<=0;sample_pending<=sample_enable || prefetch_enable;
  if(rst)begin
   ws<=STOP;rs<=RI;phase<=0;rclk<=0;rrst<=0;wrst<=1;wen<=0;busy<=0;done<=0;error<=0;
   vs<=3;hs<=0;vp<=1;hp<=0;chp<=0;initialized<=0;cycle_active<=0;field_open<=0;
   raw_high<=0;counted_high<=0;rows<=0;w_total<=0;r_total<=0;index<=0;timer<=0;period_counter<=0;resets<=0;
   min_href<=32'hffffffff;max_href<=0;last_rows<=0;last_read_bytes<=0;read_at_frame_end<=0;
   next_x<=0;next_y<=0;pixel_x<=0;pixel_y<=0;pixel<=0;pixel_other<=0;preceding_byte<=0;
   sample_pending<=0;sample_odd<=0;sample_last<=0;sensor_frames<=0;read_frames<=0;sensor_period<=0;max_occupancy<=0;
  end else begin
   vs<={vs[0],vsync};hs<={hs[0],href};vp<=frame_sync;hp<=hs[1];chp<=counted_href;
   if(hs[1]&&!hp)raw_high<=1;else if(hs[1])raw_high<=raw_high+1'b1;
   if(counted_href&&!chp)counted_high<=1;else if(counted_href)counted_high<=counted_high+1'b1;
   phase<=(phase==PERIOD-1)?0:phase+1'b1;
   if(phase==PERIOD/2-1)rclk<=!rrst || (rs==READ&&cycle_active);
   if(phase==PERIOD-1)rclk<=0;
   // Phase0 sampling consumes the prior cycle byte before admitting the next.
   if(phase==0)cycle_active<=credit && (!sample_enable || available>READ_GUARD);
   if(busy)timer<=timer+1'b1;
   if(ws==RUN)begin
    period_counter<=period_counter+1'b1;
    if(available>max_occupancy)max_occupancy<=available;
    if(rise)begin field_open<=1;rows<=0;sensor_period<=period_counter;period_counter<=1;end
    if(row&&field_open)begin
     rows<=rows+1'b1;w_total<=w_total+LINE;
     if(counted_high<min_href)min_href<=counted_high;
     if(counted_high>max_href)max_href<=counted_high;
    end
    if(fall)begin field_open<=0;last_rows<=rows+(row?1:0);sensor_frames<=sensor_frames+1'b1;read_at_frame_end<=index;end
   end
   if(prefetch_enable)begin sample_odd<=0;sample_last<=0;end
   if(sample_enable)begin
    sample_odd<=index[0];sample_last<=index==N-1;
    index<=index+1'b1;r_total<=r_total+1'b1;
    if(index==N-1)rs<=DRAIN;
   end
   if(sample_pending&&error==0)begin
    if(sample_odd==Y_BYTE)begin
     pixel_valid<=1;pixel<=io_sample;pixel_other<=preceding_byte;pixel_x<=next_x;pixel_y<=next_y;
     if(next_x==W-1)begin next_x<=0;next_y<=next_y+1'b1;end else next_x<=next_x+1'b1;
    end
    if(sample_odd!=Y_BYTE)preceding_byte<=io_sample;
    if(sample_last)begin busy<=0;done<=1;rs<=RI;read_frames<=read_frames+1'b1;last_read_bytes<=N;end
   end
   if(start&&!busy&&!pause&&error==0)begin
    busy<=1;index<=0;next_x<=0;next_y<=0;timer<=0;
    if(ws==STOP)begin
     ws<=PRIME_BLANK;rs<=WAIT_HEAD;wrst<=0;wen<=0;rrst<=0;initialized<=0;
     w_total<=0;r_total<=0;rows<=0;field_open<=0;min_href<=32'hffffffff;max_href<=0;max_occupancy<=0;
    end else rs<=ARM;
   end
   case(ws)
    PRIME_BLANK:if(!hs[1])ws<=PRIME_WAIT;
    PRIME_WAIT:if(hs[1]&&frame_sync)begin wen<=1;ws<=PRIME_ROW;end
    PRIME_ROW:if(raw_fall)begin
     wen<=0;if(raw_high>=HREF_MIN)begin wrst<=1;ws<=WAIT_BLANK;end else ws<=PRIME_BLANK;
    end
    WAIT_BLANK:if(!frame_sync)ws<=WAIT_START;
    WAIT_START:if(rise)begin ws<=RUN;wen<=1;rows<=0;field_open<=1;period_counter<=1;end
    default:begin end
   endcase
   if(ws==RUN)case(rs)
    WAIT_HEAD:if(w_total>=HEAD_ROWS*LINE&&phase==0)begin resets<=0;rs<=READ_RESET;end
    READ_RESET:if(phase==0)begin
     if(resets==4)begin rrst<=1;initialized<=1;r_total<=1;index<=1;rs<=READ;cycle_active<=1;end
     else resets<=resets+1'b1;
    end
    ARM:if(phase==0&&credit)begin rs<=READ;cycle_active<=1;end
    default:begin end
   endcase
   // Explicit pause discards only future/unclaimed bytes, after owned pixels drain.
   if(ws==RUN&&pause&&!busy)begin ws<=STOP;wen<=0;rrst<=0;initialized<=0;rs<=RI;sample_pending<=0;end
   if(error==0 && ((ws==RUN&&fall&&rows+(row?1:0)!=H) ||
      (ws==RUN&&available>FIFO_BYTES-LINE-128) || (busy&&timer==TIMEOUT-1) ||
      (ws==RUN&&row&&!field_open)))begin
    error<=(busy&&timer==TIMEOUT-1)?8'h23:(available>FIFO_BYTES-LINE-128)?8'h22:
      (row&&!field_open)?8'h24:8'h21;
    ws<=FAULT;rs<=RI;wen<=0;rrst<=0;busy<=0;sample_pending<=0;
   end
  end
 end
endmodule
