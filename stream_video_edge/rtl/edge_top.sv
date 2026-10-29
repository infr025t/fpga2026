`timescale 1ns/1ps
module edge_top(input wire clk100,btnC,input wire[15:0]sw,
 input wire[7:0]cam_data,input wire cam_vsync,cam_href,
 inout wire cam_sioc,cam_siod,cam_rst_n,
 output wire cam_wrst_n,cam_rclk,cam_rrst_n,cam_wen,uart_txd,output wire[15:0]led);
 (* ASYNC_REG="TRUE" *)reg[1:0]reset_pipe=3;
 (* ASYNC_REG="TRUE" *)reg[15:0]sm=0,ss=0;
 reg[15:0]stable=0;reg[19:0]debounce=0;reg trigger=0,start=0,rejected=0,finished=0;
 reg[23:0]power_count=0;reg[27:0]warmup=0;reg[31:0]frame_id=0;
 reg active_filter=0,active_view=0,active_pattern=0;
 reg[10:0]active_threshold=96;
 wire rst=reset_pipe[1];wire config_done,config_error,sl,dl;
 wire cap_busy,cap_wen,cap_done;
 wire stream_busy,stream_done,source_ready;wire[7:0]cap_error,stream_error;
 reg[7:0]adapter_error=0;
 wire busy=cap_busy||stream_busy;
 wire[7:0]error=cap_error|stream_error|adapter_error;
 wire camera_ready=config_done&&!config_error&&warmup==200000000;
 wire ready=stable[0]||camera_ready;
 wire[10:0]requested_threshold=stable[12:4]==0?(stable[2]?11'd128:11'd96):
  (stable[12:4]>=510?11'd2040:{stable[12:4],2'b0});
 wire[15:0]virtual_sw;wire[1:0]debug_control;
 wire[255:0]debug_camera;wire[127:0]debug_sync;
 wire[15:0]selected_sw=debug_control[0]?virtual_sw:sw;
`ifdef DIAG_JTAG
 diag_vio debug_bridge(.clk(clk100),.probe_in0({ss,error,2'd0,config_done,rejected,config_error,finished,busy,ready}),
 .probe_in1(debug_camera),.probe_in2(debug_sync),.probe_out0(virtual_sw),.probe_out1(debug_control));
`else
 assign virtual_sw=0;assign debug_control=0;
`endif
 assign cam_rst_n=(rst||power_count<1000000)?1'b0:1'bz;
 assign cam_sioc=sl?1'b0:1'bz;assign cam_siod=dl?1'b0:1'bz;
 assign cam_wen=cap_wen;
 ov7670_config #(.DIRECT_IO(0),.FREEZE_AEC(0),.FREEZE_AGC(0)) configure_camera(.clk(clk100),.rst(rst||power_count<2000000),
 .slow_clock(1'b0),.scene(1'b1),.sioc(cam_sioc),.siod(cam_siod),.done(config_done),.error(config_error),
 .scl_drive_low(sl),.sda_drive_low(dl));
 wire cv;wire[7:0]cp;wire[9:0]cx;wire[8:0]cy;
 camera_fifo_capture camera(.clk(clk100),.rst(rst),.start(start&&!active_pattern),.vsync(cam_vsync),.href(cam_href),.data(cam_data),
 .rclk(cam_rclk),.rrst(cam_rrst_n),.wrst(cam_wrst_n),.wen(cap_wen),.busy(cap_busy),.done(cap_done),.error(cap_error),
 .pixel_valid(cv),.pixel(cp),.pixel_x(cx),.pixel_y(cy),.debug_read_bytes(),.debug_rows(),.debug_timing(debug_camera),.debug_sync(debug_sync));
 reg pattern_valid=0,pattern_done=0;reg[9:0]px=0;reg[8:0]py=0;
 wire[7:0]pattern_pixel=(px+3*py+7)^(px>>3);
 always @(posedge clk100)begin
  pattern_done<=0;
  if(rst||start)begin adapter_error<=0;px<=0;py<=0;pattern_valid<=!rst&&active_pattern;end
  else begin
   if(cv&&(!source_ready||active_pattern))adapter_error<=8'h40;
   if(pattern_valid&&active_pattern&&source_ready)begin
    if(px==639)begin px<=0;if(py==479)begin pattern_valid<=0;pattern_done<=1;end else py<=py+1'b1;end
    else px<=px+1'b1;
   end
  end
 end
 wire dv,ds,dl1,de;wire[7:0]dp,dr,dg;wire[9:0]dx;wire[8:0]dy;wire[31:0]df;
 edge_uart_stream stream(.clk(clk100),.rst(rst),.start(start),.filter_id(active_filter),.view_edge(active_view),
 .frame_id(frame_id),.epsilon(active_filter?11'd64:11'd1024),.edge_threshold(active_threshold),
 .source_valid(active_pattern?pattern_valid:cv),.source_pixel(active_pattern?pattern_pixel:cp),
 .source_x(active_pattern?px:cx),.source_y(active_pattern?py:cy),.source_done(active_pattern?pattern_done:cap_done),
 .source_error(!active_pattern&&(cap_error!=0||adapter_error!=0)),.source_ready(source_ready),
 .uart_txd(uart_txd),.busy(stream_busy),.done(stream_done),.error(stream_error),
 .display_valid(dv),.display_pixel(dp),.display_raw(dr),.display_edge(dg),.display_x(dx),.display_y(dy),
 .display_frame_id(df),.display_sof(ds),.display_eol(dl1),.display_eof(de));
 // The public display tap is on edge_uart_stream. Board LCD wiring is kept
 // in the separate NT35510 bring-up top until its actual pins are assigned.
 always @(posedge clk100)begin
  reset_pipe<={reset_pipe[0],btnC|debug_control[1]};sm<=selected_sw;ss<=sm;start<=0;
  if(rst)begin
   power_count<=0;warmup<=0;stable<=ss;debounce<=0;trigger<=ss[15];rejected<=0;finished<=0;
   frame_id<=0;active_filter<=0;active_view<=0;active_pattern<=0;active_threshold<=96;
  end else begin
   if(power_count<2000000)power_count<=power_count+1'b1;
   if(!config_done)warmup<=0;else if(warmup<200000000)warmup<=warmup+1'b1;
   if(ss==stable)debounce<=0;else if(&debounce)begin stable<=ss;debounce<=0;end else debounce<=debounce+1'b1;
   trigger<=stable[15];
   if(stable[15]&&!trigger)begin
    if(ready&&!busy&&error==0)begin
     start<=1;rejected<=0;finished<=0;frame_id<=frame_id+1'b1;
     active_filter<=stable[2];active_view<=stable[1];active_pattern<=stable[0];
     active_threshold<=requested_threshold;
    end else rejected<=1;
   end
   if(stream_done)finished<=1;
  end
 end
 assign led=stable[14]?{error,8'd0}:
 {(rejected||(|error)),finished,8'd0,active_filter,active_view,active_pattern,stream_busy,cap_busy,ready};
endmodule


