`timescale 1ns/1ps
// Drive the external SCCB, VSYNC and FIFO pins, then verify the real UART.
// Three complete packets: synthetic while the camera NACKs, followed by two
// distinct external frames after automatic recovery and two discarded captures.
module tb_top_recovery;
  localparam integer W=8,H=6,OW=W-2,OH=H-2,N=OW*OH,CPB=4;
  localparam integer RESET_CYCLES=5,SETTLE_CYCLES=7,RETRY_CYCLES=31;
  localparam integer FRAME_CYCLES=13,TIMEOUT_CYCLES=512;
  reg clk=0;always #5 clk=~clk;
  reg btnC=1;reg[15:0]sw=16'h0001;
  reg vsync=1,href=0;
  tri1 scl,sda,cam_reset;
  wire tx,rclk,rrst,wen;wire[15:0]led;
  reg[7:0]fifo_data=0;
  stream_top #(.W(W),.H(H),.UART_DIV(CPB),.START_DELAY(9),
    .FRAME_DELAY(FRAME_CYCLES),.CAM_RESET_CYCLES(RESET_CYCLES),
    .CAM_SETTLE_CYCLES(SETTLE_CYCLES),.CAM_RETRY_CYCLES(RETRY_CYCLES),
    .CAPTURE_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut(
    .clk100(clk),.btnC(btnC),.sw(sw),.cam_data(fifo_data),.cam_vsync(vsync),.cam_href(href),
    .cam_rst_n(cam_reset),.cam_sioc(scl),.cam_siod(sda),.cam_rclk(rclk),
    .cam_rrst_n(rrst),.cam_wen(wen),.uart_txd(tx),.led(led));
  defparam dut.config_camera.QUARTER_CYCLES=2;
  defparam dut.config_camera.POWER_WAIT=3;
  defparam dut.config_camera.REG_WAIT=2;
  defparam dut.read_camera.QUARTER_CYCLES=2;
  defparam dut.capture_camera.FLUSH_CYCLES=3;

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

  integer cycle=0,last_error_cycle=-1,last_reset_cycle=0,last_release_cycle=0;
  integer retry_resets=0,capture_attempts=0,send_attempts=0,capture_sofs=0;
  integer capture_pixels=0,capture_frame_pixels=0,capture_completions=0;
  integer writes[0:5];
  reg previous_reset=0,previous_config_reset=1,previous_config_error=0;
  reg first_reset_released=0;
  integer monitor_expected,monitor_x,monitor_y;
  always @(negedge clk)begin
    cycle=cycle+1;
    if(!dut.rst)begin
      if(dut.config_error && !previous_config_error)begin
        if(scl!==1'b1 || sda!==1'b1 || bus_active)
          $fatal(1,"configuration failure published before SCCB STOP");
        last_error_cycle=cycle;
      end
      if(previous_reset && cam_reset===1'b0)begin
        if(last_error_cycle<0 || cycle-last_error_cycle!=RETRY_CYCLES)
          $fatal(1,"physical camera retry delay %0d expected %0d",
            cycle-last_error_cycle,RETRY_CYCLES);
        retry_resets=retry_resets+1;last_reset_cycle=cycle;
        if(dut.camera_fault!==1'b1)$fatal(1,"camera fault lost on retry reset");
      end
      if(!previous_reset && cam_reset===1'b1)begin
        if(first_reset_released && cycle-last_reset_cycle!=RESET_CYCLES)
          $fatal(1,"physical camera reset pulse width");
        first_reset_released=1;last_release_cycle=cycle;
      end
      if(previous_config_reset && !dut.camera_config_rst &&
          cycle-last_release_cycle!=SETTLE_CYCLES)
        $fatal(1,"configuration resumed before camera settling delay");
      if(last_error_cycle>=0 && cycle>last_error_cycle && !dut.config_done &&
          dut.camera_fault!==1'b1)
        $fatal(1,"camera fault indication disappeared during retry");
    end
    previous_reset=cam_reset;previous_config_reset=dut.camera_config_rst;
    previous_config_error=dut.config_error;
  end
  always @(posedge clk)if(!dut.rst)begin
    if(dut.capture_start)begin
      capture_attempts=capture_attempts+1;
      if(!dut.config_done || dut.sw_sync[15])$fatal(1,"capture started before ready or while paused");
    end
    if(dut.cap_sof)begin capture_sofs=capture_sofs+1;capture_frame_pixels=0;end
    if(dut.cap_valid)begin
      monitor_expected=source_y(dut.frame_id,capture_frame_pixels%W,capture_frame_pixels/W);
      if(dut.cap_pixel!==monitor_expected[7:0])
        $fatal(1,"FIFO luminance byte mismatch frame %0d pixel %0d",dut.frame_id,capture_frame_pixels);
      capture_pixels=capture_pixels+1;capture_frame_pixels=capture_frame_pixels+1;
    end
    if(dut.cap_done)begin
      capture_completions=capture_completions+1;
      if(capture_frame_pixels!=W*H)$fatal(1,"capture ended with missing luminance bytes");
    end
    if(dut.framebuffer_write)begin
      if(dut.frame_id!=1 && dut.frame_id!=4 && dut.frame_id!=5)
        $fatal(1,"failed capture wrote a framebuffer pixel");
      monitor_x=writes[dut.frame_id]%OW+1;monitor_y=writes[dut.frame_id]/OW+1;
      monitor_expected=source_y(dut.frame_id,monitor_x,monitor_y);
      if(dut.core_addr!==writes[dut.frame_id] || dut.core_pixel!==monitor_expected[7:0])
        $fatal(1,"framebuffer did not rewrite fresh pixels frame %0d address %0d",
          dut.frame_id,writes[dut.frame_id]);
      writes[dut.frame_id]=writes[dut.frame_id]+1;
    end
    if(dut.tx_start)begin
      send_attempts=send_attempts+1;
      if(writes[dut.frame_id]!=N)$fatal(1,"partial or failed image was sent");
    end
  end

  function integer source_y(input integer frame,x,y);
    begin
      case(frame)
        1:source_y=(x>=W/4 && x<W/2 && y>=H/4 && y<3*H/4)?220:((x+y)%96);
        4:source_y=((x+y)%3==0)?200+x:20+3*y+x;
        5:source_y=((2*x+y)%4==0)?240-y:60+x+y;
        default:source_y=-1;
      endcase
    end
  endfunction
  task camera_byte(input[7:0]value);
    begin @(negedge clk);cam_write_data=value;#2;cam_pclk=1;#2;cam_pclk=0;end
  endtask
  task supply_camera_frame(input integer expected_frame);
    integer x,y,value;
    begin
      wait(dut.capture_start);@(negedge clk);
      if(dut.frame_id!=expected_frame)$fatal(1,"wrong external capture frame id");
      vsync=0;href=0;repeat(6)@(negedge clk);vsync=1;
      wait(wen);@(negedge clk);
      if(dut.cap_error)$fatal(1,"new capture did not clear old timeout");
      for(y=0;y<H;y=y+1)begin
        href=1;
        for(x=0;x<W;x=x+1)begin
          camera_byte(8'h80+x+y);
          value=source_y(expected_frame,x,y);camera_byte(value[7:0]);
        end
        @(negedge clk);href=0;
      end
      if(write_pointer!=W*H*2)$fatal(1,"WEN/HREF gated camera write was incomplete");
      repeat(2)@(negedge clk);vsync=0;
      wait(!wen);@(negedge clk);sw=16'h8000;
      repeat(6)@(negedge clk);vsync=1;
    end
  endtask
  task check_paused(input integer attempts,frame);
    begin
      repeat(FRAME_CYCLES+40)@(negedge clk);
      if(capture_attempts!=attempts || dut.frame_id!=frame || dut.state!=0 ||
          dut.cap_busy || dut.tx_busy || wen || tx!==1'b1)
        $fatal(1,"pause did not hold the next acquisition at frame boundary");
    end
  endtask

  reg[7:0]received[0:32+N+2-1];
  reg[15:0]crc;
  integer fd,packet_count=0,packet,frame,i,k,expected_value,ref_count,ref_x,ref_y,x,y;
  function[15:0]update_crc(input[15:0]c,input[7:0]b);
    reg[15:0]v;integer bit_index;
    begin v=c^{b,8'b0};for(bit_index=0;bit_index<8;bit_index=bit_index+1)
      v=v[15]?(v<<1)^16'h1021:v<<1;update_crc=v;end
  endfunction
  function[31:0]u32(input integer offset);
    u32={received[offset+3],received[offset+2],received[offset+1],received[offset]};
  endfunction
  function[15:0]u16(input integer offset);
    u16={received[offset+1],received[offset]};
  endfunction
  task get_byte(output[7:0]b);
    integer bit_index;
    begin
      @(negedge tx);#(CPB*10/2);
      if(tx!==0)$fatal(1,"UART start bit");
      for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin #(CPB*10);b[bit_index]=tx;end
      #(CPB*10);if(tx!==1)$fatal(1,"UART stop bit");
    end
  endtask
  initial begin
    for(k=0;k<6;k=k+1)writes[k]=0;
    for(k=0;k<W*H*2;k=k+1)fifo_memory[k]=8'hb7;
    fd=$fopen("top_recovery_wire.bin","wb");
    if(fd==0)$fatal(1,"cannot open top_recovery_wire.bin");
    for(packet=0;packet<3;packet=packet+1)begin
      frame=(packet==0)?1:packet+3;
      for(i=0;i<32+N+2;i=i+1)begin get_byte(received[i]);$fwrite(fd,"%c",received[i]);end
      if(u32(0)!==32'h31475046 || received[4]!==8'd1 || received[5]!==8'd0 ||
          u16(6)!==OW || u16(8)!==OH || u16(10)!==16'd160 ||
          u32(12)!==frame || u32(16)!==N)
        $fatal(1,"recovery UART header packet %0d",packet);
      ref_count=0;ref_x=0;ref_y=0;
      for(y=1;y<=OH;y=y+1)for(x=1;x<=OW;x=x+1)begin
        expected_value=source_y(frame,x,y);
        if(received[32+(y-1)*OW+x-1]!==expected_value[7:0])
          $fatal(1,"recovery UART stale/wrong pixel frame %0d x=%0d y=%0d",frame,x,y);
        if(expected_value>=128)begin ref_count=ref_count+1;ref_x=ref_x+x;ref_y=ref_y+y;end
      end
      if(u32(20)!==ref_count || u32(24)!==ref_x || u32(28)!==ref_y)
        $fatal(1,"recovery UART stale/wrong brightness statistics frame %0d",frame);
      crc=16'hffff;for(i=4;i<32+N;i=i+1)crc=update_crc(crc,received[i]);
      if(u16(32+N)!==crc)$fatal(1,"recovery UART CRC frame %0d",frame);
      packet_count=packet_count+1;
    end
    $fclose(fd);
  end

  initial begin
    repeat(5)@(negedge clk);btnC=0;
    wait(dut.pattern_active);repeat(200)@(negedge clk);sw=16'h8000;
    wait(packet_count==1);wait(dut.tx_done);@(negedge clk);
    if(nack_transactions<2 || retry_resets<2 || dut.config_done || capture_attempts!=0 ||
        dut.camera_fault!==1'b1 || led[15]!==1'b1)
      $fatal(1,"synthetic output did not survive repeated absent-camera NACK/retries");
    check_paused(0,1);
    // Reconnect only during physical reset; the complete register sequence
    // must succeed without touching the user reset button or internal state.
    @(negedge cam_reset);@(negedge clk);camera_present=1;
    if(dut.camera_fault!==1'b1 || led[15]!==1'b1)
      $fatal(1,"retry cleared the visible error before successful configuration");
    wait(dut.config_done);repeat(3)@(negedge clk);
    if(ack_transactions!=39 || dut.config_error || dut.camera_fault || led[15])
      $fatal(1,"camera did not recover all 39 configuration writes automatically");
    check_paused(0,1);

    // Missing blanking: no SOF, image write or UART packet may escape.
    sw=0;wait(dut.capture_start);wait(dut.cap_busy);
    wait(dut.cap_error);@(negedge clk);sw=16'h8000;
    if(dut.frame_id!=2 || capture_sofs!=0 || capture_pixels!=0 || send_attempts!=1 ||
        packet_count!=1 || wen || !rrst || led[15]!==1'b1)
      $fatal(1,"missing VSYNC blanking was not discarded cleanly");
    check_paused(1,2);

    // Missing end-of-frame: WEN was active but must be released on timeout.
    sw=0;wait(dut.capture_start);@(negedge clk);vsync=0;
    repeat(6)@(negedge clk);vsync=1;wait(wen);@(negedge clk);sw=16'h8000;
    wait(dut.cap_error);@(negedge clk);
    if(dut.frame_id!=3 || capture_sofs!=0 || capture_pixels!=0 || send_attempts!=1 ||
        packet_count!=1 || wen || !rrst || led[15]!==1'b1)
      $fatal(1,"missing frame end was not discarded cleanly");
    check_paused(2,3);

    // Two distinct complete external images prove recovery overwrites both
    // image memory and statistics, and pause/resume does not replay a frame.
    sw=0;supply_camera_frame(4);
    wait(packet_count==2);wait(dut.tx_done);@(negedge clk);
    if(dut.cap_error || led[15])$fatal(1,"capture error did not clear on recovery");
    check_paused(3,4);
    sw=0;supply_camera_frame(5);
    wait(packet_count==3);wait(dut.tx_done);@(negedge clk);check_paused(4,5);
    if(send_attempts!=3 || capture_sofs!=2 || capture_completions!=2 ||
        capture_pixels!=W*H*2 || fifo_written!=W*H*4 ||
        writes[1]!=N || writes[2]!=0 || writes[3]!=0 || writes[4]!=N || writes[5]!=N)
      $fatal(1,"recovery frame totals");
    $display("PASS top recovery three UART frames: synthetic during NACK, two fresh FIFO frames; timed reset retry, sticky fault, two discarded VSYNC timeouts, pause/resume, pixels/statistics/CRC");
    $display("INFO recovery physical retries=%0d NACK transactions=%0d ACK configuration writes=%0d capture attempts=%0d",
      retry_resets,nack_transactions,ack_transactions,capture_attempts);
    $finish;
  end
  initial begin #5000000;$fatal(1,"top recovery timeout");end
endmodule
