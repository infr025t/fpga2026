`timescale 1ns/1ps
module tb_vision_top;
  wire a,b,c,d,e,f,g;
  vision_camera_case camera_case(a);
  vision_pattern_case #(.SCALE(1),.FILE_NAME("vision_scale1.txt")) full_size(b);
  vision_pattern_case #(.SCALE(4),.FILE_NAME("vision_scale4.txt")) thumbnail(c);
  vision_watchdog_case watchdog(d);
  vision_decimate_case #(.RATE(1)) every_two(e);
  vision_decimate_case #(.RATE(2)) every_four(f);
  vision_decimate_case #(.RATE(3)) every_eight(g);
  initial begin wait(a && b && c && d && e && f && g);
    $display("PASS standalone vision: absent PC/display, whole-frame drop, raw/enhanced, scales 1/2/4, real SCCB/FIFO, line rejection, VSYNC recovery, watchdog, pause/reset and counters");$finish;end
  initial begin #10000000;$fatal(1,"standalone vision timeout");end
endmodule
module vision_camera_case(output reg finished=0);
  localparam integer W=8,H=8,SCALE=2,DW=2,DH=2;
  reg clk=0;always #5 clk=~clk;
  reg btnC=1;reg[15:0]sw=16'h0047;
  reg vsync=1,href=0;reg[7:0]fifo_data=0;
  tri1 scl,sda,cam_reset;wire tx,rclk,rrst,wen;wire[15:0]led;
  reg display_ready=0;wire dv,sof,eol,eof,processed;wire[7:0]dp;wire[31:0]did;
  wire[31:0]frame_id,frames,shown,drops,skips,caperr,lineerr,inover,procerr,disperr,fps,latency;
  wire[15:0]width,height;
  vision_top #(.W(W),.H(H),.DISPLAY_SCALE(SCALE),.CLOCK_HZ(1024),.PATTERN_DIV(1),
    .START_DELAY(7),.FRAME_DELAY(13),.CAM_RESET_CYCLES(5),.CAM_SETTLE_CYCLES(7),
    .CAM_RETRY_CYCLES(31),.CAPTURE_TIMEOUT_CYCLES(2048),.PROCESS_TIMEOUT_CYCLES(10000),
    .CAMERA_READ_PERIOD(10),.CAMERA_FLUSH_CYCLES(3)) dut(
    clk,btnC,sw,fifo_data,vsync,href,scl,sda,cam_reset,rclk,rrst,wen,tx,led,
    display_ready,dv,dp,sof,eol,eof,did,processed,width,height,
    frame_id,frames,shown,drops,skips,caperr,lineerr,inover,procerr,disperr,fps,latency);
  defparam dut.camera.config_camera.QUARTER_CYCLES=2;
  defparam dut.camera.config_camera.POWER_WAIT=3;
  defparam dut.camera.config_camera.REG_WAIT=2;
  defparam dut.camera.read_camera.QUARTER_CYCLES=2;
  // SCCB sink watches bus edges, including START/STOP. It only pulls the
  // ninth bit low; no sequencer state or internal ACK signal is overridden.
  reg camera_present=0,sink_ack=0,bus_active=0;
  integer bus_bit=0,bus_bytes=0,nack_transactions=0,ack_transactions=0;
  reg[7:0]bus_shift=0,bus_address=0;
  assign sda=sink_ack?1'b0:1'bz;
  always @(negedge sda)if(scl===1'b1)begin
    if(bus_active)$fatal(1,"unexpected SCCB START without STOP");
    bus_active=1;bus_bit=0;bus_bytes=0;bus_shift=0;bus_address=0;
  end
  always @(posedge scl)if(bus_active)begin
    if(bus_bit<8)begin
      bus_shift={bus_shift[6:0],sda};bus_bit=bus_bit+1;
      if(bus_bit==8)begin
        if(bus_bytes==0)bus_address=bus_shift;
        bus_bytes=bus_bytes+1;
      end
    end else bus_bit=9;
  end
  always @(negedge scl)begin
    if(bus_active && bus_bit==8)sink_ack=camera_present;
    else begin
      sink_ack=0;
      if(bus_bit==9)begin bus_bit=0;bus_shift=0;end
    end
  end
  always @(posedge sda)if(scl===1'b1 && bus_active)begin
    if(bus_address!==8'h42 && bus_address!==8'h43)
      $fatal(1,"bad SCCB device address %02x",bus_address);
    if(bus_address==8'h42 && bus_bytes==3)begin
      if(camera_present)ack_transactions=ack_transactions+1;
      else nack_transactions=nack_transactions+1;
    end
    bus_active=0;
  end

  // A camera writes UYVY bytes into a behavioral AL422 while WEN and HREF
  // are high. VSYNC drives its active-low write reset. RCLK independently
  // resets/advances the read pointer, presenting byte zero on its first edge.
  reg cam_pclk=0;reg[7:0]cam_write_data=0;
  reg[7:0]fifo_memory[0:W*H*2-1];
  integer write_pointer=0,read_pointer=0,fifo_written=0;
  always @(posedge cam_pclk or negedge vsync)begin
    if(!vsync)write_pointer=0;
    else if(wen && href)begin
      if(write_pointer>=W*H*2)$fatal(1,"camera wrote too many FIFO bytes");
      fifo_memory[write_pointer]=cam_write_data;
      write_pointer=write_pointer+1;fifo_written=fifo_written+1;
    end
  end
  always @(posedge rclk)begin
    if(!rrst)begin read_pointer=0;fifo_data<=0;end
    else begin
      fifo_data<=(read_pointer<W*H*2)?fifo_memory[read_pointer]:8'hde;
      read_pointer=read_pointer+1;
    end
  end


  integer packets=0,index=0,expected_ids[0:3],fd,cycle=0,expected_processed;
  reg held=0;reg[43:0]held_data;reg run_display=0,saw_fps=0;
  always @(posedge clk)begin
    cycle=cycle+1;
    if(fps!=0)saw_fps=1;
    if(dut.rst)held=0;
    else begin
      if(tx!==1'b1)$fatal(1,"disabled optional PC interface transmitted");
      if(held && {did,processed,sof,eol,eof,dp}!==held_data)$fatal(1,"vision display changed under stall");
      held=dv && !display_ready;held_data={did,processed,sof,eol,eof,dp};
      if(dv && frames<did && did<=4)$fatal(1,"display exposed uncommitted processing frame");
      if(dv && display_ready)begin
        expected_processed=(did!=4);
        if(packets>=4 || did!==expected_ids[packets] || processed!==expected_processed ||
           sof!==(index==0) || eol!==(index%DW==DW-1) || eof!==(index==DW*DH-1))
          $fatal(1,"vision display ordering/raster frame=%0d index=%0d",did,index);
        $fdisplay(fd,"%0d %0d %0d %0d %0d",did,processed,2+(index%DW)*SCALE,2+(index/DW)*SCALE,dp);
        if(eof)begin packets=packets+1;index=0;end else index=index+1;
      end
    end
  end
  always @(negedge clk)if(run_display)display_ready=(cycle%3!=1);
  function[7:0]camera_y(input integer frame,x,y);
    camera_y=(x*19+y*23+frame*11)%256;
  endfunction
  task camera_byte(input[7:0]value);
    begin @(negedge clk);cam_write_data=value;cam_pclk=0;@(negedge clk);cam_pclk=1;end
  endtask
  task supply_frame(input integer frame,rows);
    integer x,y;
    begin
      wait(dut.capture_start);@(negedge clk);if(frame_id!=frame)$fatal(1,"camera attempt id");
      vsync=0;href=0;repeat(6)@(negedge clk);vsync=1;wait(wen);@(negedge clk);
      for(y=0;y<rows;y=y+1)begin
        href=1;
        for(x=0;x<W;x=x+1)begin camera_byte(8'h80);camera_byte(camera_y(frame,x,y));end
        @(negedge clk);href=0;repeat(3)@(negedge clk);
      end
      repeat(3)@(negedge clk);vsync=0;
      wait(!wen);@(negedge clk);sw=16'h8046;
      repeat(6)@(negedge clk);vsync=1;
    end
  endtask
  initial begin
    expected_ids[0]=1;expected_ids[1]=2;expected_ids[2]=4;expected_ids[3]=6;
    for(integer k=0;k<W*H*2;k=k+1)fifo_memory[k]=8'hb7;
    fd=$fopen("vision_camera.txt","w");if(!fd)$fatal(1,"vision export");$fdisplay(fd,"%0d %0d %0d",W,H,SCALE);
    repeat(5)@(negedge clk);btnC=0;
    wait(frame_id==3 && dut.pattern_active);@(negedge clk);sw=16'h8047;
    wait(frames==3);repeat(4)@(negedge clk);
    if(frame_id!=3 || drops!=1 || dut.display_queue.level!=2 || shown!=0 || !dut.camera.camera_fault)
      $fatal(1,"vision depended on absent PC/display or failed whole-frame drop");
    run_display=1;wait(packets==2);@(negedge clk);run_display=0;display_ready=0;
    sw=16'h0045;wait(frame_id==4 && dut.pattern_active);@(negedge clk);sw=16'h8047;
    wait(frames==4);run_display=1;wait(packets==3);@(negedge clk);run_display=0;display_ready=0;
    // Reconnect during physical reset, without any user reset button.
    @(negedge cam_reset);@(negedge clk);camera_present=1;
    wait(dut.config_done);repeat(5)@(negedge clk);
    if(ack_transactions!=39 || dut.camera_fault)$fatal(1,"vision camera configuration recovery");
    sw=16'h0046;supply_frame(5,H-1);wait(dut.state==0);repeat(4)@(negedge clk);
    if(lineerr!=1 || frames!=4 || dv)$fatal(1,"wrong camera line count was processed");
    sw=16'h0046;supply_frame(6,H);wait(frames==5);run_display=1;wait(packets==4);
    @(negedge clk);run_display=0;display_ready=0;
    sw=16'h0046;wait(dut.capture_start);@(negedge clk);sw=16'h8046;
    wait(caperr==1);repeat(5)@(negedge clk);
    if(frame_id!=7 || frames!=5 || lineerr!=1 || inover || procerr || disperr || !saw_fps || latency==0 || wen)
      $fatal(1,"vision recovery/monitor totals");
    repeat(20)@(negedge clk);if(frame_id!=7)$fatal(1,"vision pause started another frame");
    $fclose(fd);
    btnC=1;repeat(24)@(negedge clk);
    if(frame_id || frames || shown || drops || lineerr || caperr || dv || dut.display_queue.level)
      $fatal(1,"vision manual reset did not clear state");
    finished=1;
  end
endmodule
module vision_pattern_case #(parameter integer SCALE=1,parameter FILE_NAME="vision_scale1.txt")(output reg finished=0);
  reg clk=0;always #5 clk=~clk;
  reg btn=1;reg[15:0]sw=16'h0047;tri1 scl,sda,cr;
  wire dv,sof,eol,eof,view,tx;wire[7:0]pixel;wire[31:0]id,attempts,frames;
  wire[15:0]width,height;integer fd,index=0,packets=0;
  vision_top #(.W(8),.H(8),.DISPLAY_SCALE(SCALE),.PATTERN_DIV(1),.CLOCK_HZ(1024),
    .START_DELAY(3),.FRAME_DELAY(11),.CAM_RESET_CYCLES(5),.CAM_SETTLE_CYCLES(7)) dut(
    .clk100(clk),.btnC(btn),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_sioc(scl),.cam_siod(sda),.cam_rst_n(cr),.uart_txd(tx),.display_ready(1'b1),
    .display_valid(dv),.display_pixel(pixel),.display_sof(sof),.display_eol(eol),.display_eof(eof),
    .display_frame_id(id),.display_processed(view),.display_width(width),.display_height(height),
    .frame_id(attempts),.processed_frames(frames));
  always @(posedge clk)if(!dut.rst && dv)begin
    if(id!=packets+1 || !view || frames<id || sof!==(index==0) ||
       eol!==(index%width==width-1) || eof!==(index==width*height-1))$fatal(1,"vision scale raster/commit");
    $fdisplay(fd,"%0d %0d %0d %0d %0d",id,view,2+(index%width)*SCALE,2+(index/width)*SCALE,pixel);
    if(eof)begin packets=packets+1;index=0;end else index=index+1;
  end
  initial begin
    fd=$fopen(FILE_NAME,"w");if(!fd)$fatal(1,"scale export");$fdisplay(fd,"8 8 %0d",SCALE);
    repeat(4)@(negedge clk);btn=0;
    wait(attempts==3 && dut.pattern_active);@(negedge clk);sw=16'h8047;
    wait(packets==3);repeat(3)@(negedge clk);$fclose(fd);finished=1;
  end
endmodule
module vision_watchdog_case(output reg finished=0);
  reg clk=0;always #5 clk=~clk;
  reg btn=1;reg[15:0]sw=16'h0047;tri1 scl,sda,cr;
  wire dv;wire[31:0]errors,frames;
  vision_top #(.W(8),.H(8),.PATTERN_DIV(20),.CLOCK_HZ(1024),.START_DELAY(3),.FRAME_DELAY(17),
    .PROCESS_TIMEOUT_CYCLES(900),.CAM_RESET_CYCLES(5),.CAM_SETTLE_CYCLES(7)) dut(
    .clk100(clk),.btnC(btn),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_sioc(scl),.cam_siod(sda),.cam_rst_n(cr),.display_ready(1'b1),.display_valid(dv),
    .processing_errors(errors),.processed_frames(frames));
  always @(posedge clk)if(!dut.rst && dv)$fatal(1,"watchdog exposed partial frame");
  initial begin
    repeat(4)@(negedge clk);btn=0;wait(errors>=2);@(negedge clk);sw=16'h8047;
    repeat(30)@(negedge clk);
    if(frames || dut.display_queue.level || dut.processing_active || dut.state!=0)
      $fatal(1,"watchdog failed clean recovery");finished=1;
  end
endmodule

module vision_decimate_case #(parameter integer RATE=1)(output reg finished=0);
  localparam integer STRIDE=(1<<RATE),EXPECTED=(9+STRIDE-1)/STRIDE;
  reg clk=0;always #5 clk=~clk;
  reg btn=1;reg[15:0]sw=16'h0047|(RATE<<8);tri1 scl,sda,cr;
  wire dv,sof,eol,eof;wire[31:0]id,attempts,frames,shown,skipped,dropped;
  integer packets=0,index=0;
  vision_top #(.W(8),.H(8),.PATTERN_DIV(1),.CLOCK_HZ(1024),.START_DELAY(3),.FRAME_DELAY(11),
    .CAM_RESET_CYCLES(5),.CAM_SETTLE_CYCLES(7)) dut(
    .clk100(clk),.btnC(btn),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_sioc(scl),.cam_siod(sda),.cam_rst_n(cr),.display_ready(1'b1),.display_valid(dv),
    .display_sof(sof),.display_eol(eol),.display_eof(eof),.display_frame_id(id),
    .frame_id(attempts),.processed_frames(frames),.displayed_frames(shown),
    .display_skipped(skipped),.display_dropped(dropped));
  always @(posedge clk)if(!dut.rst && dv)begin
    if(id!=1+packets*STRIDE || sof!==(index==0) || eol!==(index%4==3) || eof!==(index==15))
      $fatal(1,"display decimation raster/cadence");
    if(eof)begin packets=packets+1;index=0;end else index=index+1;
  end
  initial begin
    repeat(4)@(negedge clk);btn=0;
    wait(attempts==9 && dut.pattern_active);@(negedge clk);sw=sw|16'h8000;
    wait(frames==9 && shown==EXPECTED);repeat(4)@(negedge clk);
    if(packets!=EXPECTED || skipped!=9-EXPECTED || dropped || attempts!=9)
      $fatal(1,"display decimation counters");finished=1;
  end
endmodule
