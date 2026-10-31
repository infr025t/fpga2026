`timescale 1ns/1ps
// Independent WRST: prime before the selected frame, then keep
// WRST released through the complete read. Append without write reset.
module camera_fifo_capture_reference #(
 parameter W=640,H=480,FIFO_BYTES=393216,HEAD_ROWS=32,HREF_MIN=128,
 parameter PERIOD=50,TIMEOUT=200000000,RUNTIME_PERIOD=0,READ_GUARD=129,HREF_QUALIFY_CYCLES=64
)(input wire clk,rst,start,vsync,href,input wire[7:0]data,
 output reg rclk,rrst,wrst,wen,output wire busy,output reg done,output reg[7:0]error,
 output reg pixel_valid,output reg[7:0]pixel,output reg[9:0]pixel_x,
 output reg[8:0]pixel_y,output wire[31:0]debug_read_bytes,debug_rows,
 output wire[255:0]debug_timing,output wire[127:0]debug_sync,
 input wire[7:0]period_cycles,
 output wire debug_byte_valid,output wire[31:0]debug_byte_index,output wire[7:0]debug_byte_data);
 localparam N=W*H*2,LINE=2*W,IDLE=0,BLANK=1,FRAME=2,ACTIVE=3,FINISH=4,PRIME_BLANK=5,PRIME_WAIT=6,PRIME_ROW=7;
 localparam FLUSH_GUARD=((N>FIFO_BYTES)?N-FIFO_BYTES:0)+2*LINE+128;
 localparam R_WAIT=0,R_RESET=1,R_READ=2,R_DONE=3;
 reg[2:0]state,rs,resets;reg[7:0]phase;
 (* ASYNC_REG="TRUE" *)reg[1:0]vs,hs;
 reg vp,hp,cycle_active,first_ended,flush_armed,flush_done;
 reg[31:0]timer,rows,extra_rows,high_cycles,index;
 reg[9:0]next_x;reg[8:0]next_y;reg[7:0]active_period;
 wire[7:0]period=RUNTIME_PERIOD?active_period:PERIOD;
 // Passive diagnostic counters. They do not participate in FIFO control.
 reg[31:0]frame_cycles,read_at_frame_end,min_href,max_href,max_lag,paused_periods;
 wire frame_sync;wire[31:0]last_long_low,rejected_low,max_rejected_low,last_raw_low;
 reg bad_low_pending=0;reg[31:0]bad_low_ticks=0;
 vsync_low_filter #(.MIN_LOW(64)) qualify_vsync(.clk(clk),.rst(rst),.clear_stats(start&&state==IDLE),
  .sync_in(vs[1]),.sync_out(frame_sync),.last_long_low(last_long_low),.rejected(rejected_low),
  .max_rejected(max_rejected_low),.last_raw_low(last_raw_low));
 wire rise=frame_sync&&!vp,fall=!frame_sync&&vp,hfall=hp&&!hs[1];
 wire qualified=hfall&&high_cycles>=HREF_MIN; // Preserve original write-control event.
 wire counted_href;
 reg counted_hp=0;reg[31:0]counted_high_cycles=0;
 href_stable_filter #(.STABLE_CYCLES(HREF_QUALIFY_CYCLES)) qualify_href_count(
  .clk(clk),.rst(rst),.sync_in(hs[1]),.sync_out(counted_href));
 wire counted_fall=counted_hp&&!counted_href;
 wire counted_row=counted_fall&&counted_high_cycles>=HREF_MIN;
 wire[31:0]completed=rows*LINE;
 wire credit=flush_done||(index+READ_GUARD<=completed);
 assign busy=state!=IDLE;
 assign debug_read_bytes=index;assign debug_rows=rows;
 assign debug_timing={paused_periods,max_lag,max_href,min_href,read_at_frame_end,frame_cycles,index,rows};
 assign debug_sync={bad_low_ticks,max_rejected_low,rejected_low,last_long_low};
 // Passive observation only; no path back into capture timing or control.
 assign debug_byte_valid=!rst && state==ACTIVE && rs==R_READ && cycle_active && phase==period-1;
 assign debug_byte_index=index;
 assign debug_byte_data=data;
 always @(posedge clk)begin
  pixel_valid<=0;done<=0;
  if(rst)begin
   state<=IDLE;rs<=R_WAIT;phase<=0;rclk<=0;rrst<=0;wrst<=1;wen<=0;done<=0;error<=0;
   vs<=3;hs<=0;vp<=1;hp<=0;cycle_active<=0;first_ended<=0;flush_armed<=0;flush_done<=0;
   rows<=0;extra_rows<=0;high_cycles<=0;timer<=0;resets<=0;index<=0;
   next_x<=0;next_y<=0;pixel_x<=0;pixel_y<=0;pixel<=0;active_period<=PERIOD;
   frame_cycles<=0;read_at_frame_end<=0;min_href<=32'hffffffff;max_href<=0;max_lag<=0;paused_periods<=0;
   bad_low_pending<=0;bad_low_ticks<=0;counted_hp<=0;counted_high_cycles<=0;
  end else begin
   vs<={vs[0],vsync};hs<={hs[0],href};vp<=frame_sync;hp<=hs[1];
   if(rise&&bad_low_pending)begin bad_low_ticks<=last_raw_low;bad_low_pending<=0;end
   if(state!=IDLE)timer<=timer+1'b1;
   phase<=(phase>=period-1)?0:phase+1'b1;
   if(phase==period/2-1&&(rs!=R_READ||cycle_active))rclk<=1;
   if(phase==period-1)rclk<=0;
   if(phase==0)cycle_active<=credit;
   counted_hp<=counted_href;
   if(counted_href&&!counted_hp)counted_high_cycles<=1;
   else if(counted_href)counted_high_cycles<=counted_high_cycles+1'b1;
   if(hs[1]&&!hp)high_cycles<=1;else if(hs[1])high_cycles<=high_cycles+1'b1;
   if(state==ACTIVE)begin
    if(!first_ended&&counted_row)begin
     if(counted_high_cycles<min_href)min_href<=counted_high_cycles;
     if(counted_high_cycles>max_href)max_href<=counted_high_cycles;
    end
    if(!first_ended&&fall)begin frame_cycles<=timer;read_at_frame_end<=index;end
    if(completed>=index&&completed-index>max_lag)max_lag<=completed-index;
    if(rs==R_READ&&phase==0&&!credit)paused_periods<=paused_periods+1'b1;
    if(counted_row&&!first_ended)rows<=rows+1'b1;
    // Keep raw qualified HREF for the already tested FIFO append write timing.
    if(qualified&&first_ended&&flush_armed&&!flush_done)begin
     extra_rows<=extra_rows+1'b1;
     if(extra_rows==1)begin wen<=0;flush_done<=1;end
    end
    if(fall&&!first_ended)begin first_ended<=1;wen<=0;end
    // Append commits the tail at the current write pointer, without reset.
    if(first_ended&&!flush_armed&&rise&&index>FLUSH_GUARD)begin flush_armed<=1;wen<=1;end
   end
   if(state==ACTIVE&&fall&&!first_ended&&rows+(counted_row?1:0)!=H)begin error<=8'h21;wen<=0;state<=FINISH;rs<=R_DONE;bad_low_pending<=1;end
   else if(state==ACTIVE&&completed>=index&&completed-index>FIFO_BYTES-LINE-128)begin error<=8'h22;wen<=0;state<=FINISH;rs<=R_DONE;end
   else if(state!=IDLE&&state!=FINISH&&timer==TIMEOUT-1)begin error<=8'h23;wen<=0;state<=FINISH;rs<=R_DONE;end
   else case(state)
    IDLE:if(start)begin
     active_period<=RUNTIME_PERIOD?period_cycles:PERIOD;phase<=0;cycle_active<=0;rclk<=0;
     state<=PRIME_BLANK;wrst<=0;wen<=0;error<=0;rows<=0;extra_rows<=0;index<=0;next_x<=0;next_y<=0;
     first_ended<=0;flush_armed<=0;flush_done<=0;rs<=R_WAIT;timer<=0;
     frame_cycles<=0;read_at_frame_end<=0;min_href<=32'hffffffff;max_href<=0;max_lag<=0;paused_periods<=0;
     bad_low_pending<=0;bad_low_ticks<=0;
    end
    // Reset writer in one priming HREF before selecting the next full field.
    PRIME_BLANK:if(!hs[1])state<=PRIME_WAIT;
    PRIME_WAIT:if(hs[1]&&frame_sync)begin wen<=1;state<=PRIME_ROW;end
    PRIME_ROW:if(hfall)begin
     wen<=0;
     if(qualified)begin wrst<=1;state<=BLANK;end else state<=PRIME_BLANK;
    end
    BLANK:if(!frame_sync)state<=FRAME;
    FRAME:if(rise)begin state<=ACTIVE;wen<=1;timer<=0;end
    ACTIVE:case(rs)
     R_WAIT:if(rows>=HEAD_ROWS&&phase==0)begin rrst<=0;resets<=0;rs<=R_RESET;end
     // AL422-07 prefetches byte0 while RRST is low. It is the leading U
     // byte in UYVY, so count it without emitting a pixel. The first released
     // RCLK edge outputs byte1 (Y0), rather than starting again at byte0.
     R_RESET:if(phase==0)begin if(resets==4)begin rrst<=1;index<=1;rs<=R_READ;end else resets<=resets+1'b1;end
     R_READ:begin
      // One sample at the falling edge: at least40ns after the rising edge
      // for the tested periods>=8. No early/late diagnostic comparison.
      if(cycle_active&&phase==period-1)begin
        if(index[0])begin
         pixel_valid<=1;pixel<=data;pixel_x<=next_x;pixel_y<=next_y;
         if(next_x==W-1)begin next_x<=0;next_y<=next_y+1'b1;end else next_x<=next_x+1'b1;
        end
        index<=index+1'b1;
        if(index==N-1)begin rs<=R_DONE;state<=FINISH;wen<=0;rrst<=0;end
      end
     end
     default:begin end
    endcase
    FINISH:begin state<=IDLE;done<=1;wen<=0;rrst<=0;wrst<=1;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
