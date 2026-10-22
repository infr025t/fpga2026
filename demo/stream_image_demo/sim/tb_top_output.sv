`timescale 1ns/1ps
// Complete top-level UART path, including the switches, output framebuffer,
// first-frame delay, and every runtime transition back to an image.
module tb_top_output #(parameter integer FAST_CYCLES=3);
  localparam integer W=9,H=6,OW=W-2,OH=H-2,N=OW*OH,CPB=4,MIN_AREA=4;
  localparam integer START_CYCLES=17,FRAME_CYCLES=29;
  reg clk=0;always #5 clk=~clk;
  reg btnC=1;reg[15:0]sw=16'h0001;
  tri1 scl,sda,cam_reset;
  wire tx,rclk,rrst,wen;wire[15:0]led;
  stream_top #(.W(W),.H(H),.UART_DIV(CPB),.START_DELAY(START_CYCLES),
    .FRAME_DELAY(FRAME_CYCLES),.FAST_FRAME_DELAY(FAST_CYCLES),.TARGET_MIN_AREA(MIN_AREA),
    .CAM_RESET_CYCLES(10),.CAM_SETTLE_CYCLES(12)) dut(
    .clk100(clk),.btnC(btnC),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_rst_n(cam_reset),.cam_sioc(scl),.cam_siod(sda),.cam_rclk(rclk),
    .cam_rrst_n(rrst),.cam_wen(wen),.uart_txd(tx),.led(led));

  reg[7:0]received[0:72+N+2-1];
  reg[7:0]frozen_framebuffer[0:N-1];
  reg[7:0]frozen_read_data;
  reg watching_features=0;
  integer writes[0:4],core_pixels[0:4];
  integer fd,f,i,j,k,header_bytes,payload_bytes,total,expected_byte,xx,yy;
  integer control_frame,cycle=0,wait_enter_cycle=0,launch_count=0,expected_delay;
  integer active_frame,reference_pixel,snapshot_index;
  integer ref_bright,ref_bright_x,ref_bright_y,ref_area,ref_x,ref_y;
  integer ref_x_min,ref_y_min,ref_x_max,ref_y_max;
  reg previous_rst=1,previous_fast=0;
  reg[2:0]previous_state=0;
  reg[15:0]crc;

  function[15:0] update_crc(input[15:0]c,input[7:0]b);
    reg[15:0]v;integer n;
    begin v=c^{b,8'b0};for(n=0;n<8;n=n+1)v=v[15]?(v<<1)^16'h1021:v<<1;update_crc=v;end
  endfunction
  function[31:0]u32(input integer offset);
    u32={received[offset+3],received[offset+2],received[offset+1],received[offset]};
  endfunction
  function[15:0]u16(input integer offset);
    u16={received[offset+1],received[offset]};
  endfunction
  // Independent, coordinate-based model of the synthetic source and Sobel.
  function integer source_y(input integer frame,x,y);
    reg inside_rect;
    begin
      inside_rect=(x>=W/4 && x<W/2 && y>=H/4 && y<3*H/4);
      if(frame==0)source_y=inside_rect?220:((x+y)%96);
      else if(frame==2 || frame==3)source_y=inside_rect?220:32;
      else source_y=inside_rect?32:220;
    end
  endfunction
  function integer image_y(input integer frame,x,y);
    integer gx,gy,mag;
    begin
      if(frame==0 || frame==3)image_y=source_y(frame,x,y);
      else begin
        gx=source_y(frame,x+1,y-1)+2*source_y(frame,x+1,y)+source_y(frame,x+1,y+1)
          -source_y(frame,x-1,y-1)-2*source_y(frame,x-1,y)-source_y(frame,x-1,y+1);
        gy=source_y(frame,x-1,y+1)+2*source_y(frame,x,y+1)+source_y(frame,x+1,y+1)
          -source_y(frame,x-1,y-1)-2*source_y(frame,x,y-1)-source_y(frame,x+1,y-1);
        mag=(gx<0?-gx:gx)+(gy<0?-gy:gy);
        image_y=(mag>=((frame==2)?960:160))?255:0;
      end
    end
  endfunction
  task build_reference(input integer frame);
    integer x,y,value;reg selected;
    begin
      ref_bright=0;ref_bright_x=0;ref_bright_y=0;
      ref_area=0;ref_x=0;ref_y=0;
      ref_x_min=0;ref_y_min=0;ref_x_max=0;ref_y_max=0;
      for(y=1;y<=OH;y=y+1)for(x=1;x<=OW;x=x+1)begin
        value=source_y(frame,x,y);
        if(value>=128)begin
          ref_bright=ref_bright+1;ref_bright_x=ref_bright_x+x;ref_bright_y=ref_bright_y+y;
        end
        selected=(frame==2 || frame==3)?(value>=96):(value<=96);
        if(frame!=0 && selected)begin
          if(ref_area==0)begin ref_x_min=x;ref_x_max=x;ref_y_min=y;ref_y_max=y;end
          else begin
            if(x<ref_x_min)ref_x_min=x;if(x>ref_x_max)ref_x_max=x;
            if(y<ref_y_min)ref_y_min=y;if(y>ref_y_max)ref_y_max=y;
          end
          ref_area=ref_area+1;ref_x=ref_x+x;ref_y=ref_y+y;
        end
      end
    end
  endtask
  task check_controls(input integer frame);
    begin
      if(dut.pattern_mode!==1'b1 || dut.edge_mode!==(frame==1 || frame==2 || frame==4) ||
         dut.target_enable!==(frame!=0) || dut.target_dark!==!(frame==2 || frame==3) ||
         dut.threshold!==((frame==2)?11'd960:11'd160) || dut.target_threshold!==8'd96 ||
         dut.packed_mode!==(frame==1) || dut.features_only!==(frame==2) ||
         dut.fast_frames!==(frame>=1 && frame<=3))
        $fatal(1,"top output controls changed inside frame %0d",frame);
    end
  endtask
  task get_byte(output[7:0]b);
    integer n;
    begin
      @(negedge tx);#(CPB*10/2);
      if(tx!==0)$fatal(1,"bad start bit");
      for(n=0;n<8;n=n+1)begin #(CPB*10);b[n]=tx;end
      #(CPB*10);if(tx!==1)$fatal(1,"bad stop bit");
    end
  endtask

  // Count from the first WAITING edge, so the LAUNCH edge follows N+1
  // clocks for a programmed delay of N (including the zero-delay case).
  always @(posedge clk)begin
    cycle=cycle+1;
    if(!dut.rst)begin
      if(previous_rst || (dut.state==0 && previous_state!=0))wait_enter_cycle=cycle;
      if(dut.state==1)begin
        expected_delay=(launch_count==0)?START_CYCLES:(previous_fast?FAST_CYCLES:FRAME_CYCLES);
        if(cycle-wait_enter_cycle!=expected_delay+1)
          $fatal(1,"top output wait mismatch frame %0d: %0d expected %0d",
            launch_count,cycle-wait_enter_cycle,expected_delay+1);
        if(dut.startup_complete!==(launch_count!=0))$fatal(1,"startup_complete timing");
        previous_fast=dut.fast_frames;launch_count=launch_count+1;
      end
      if(dut.features_only && (dut.framebuffer_write!==0 || dut.framebuffer_read!==0))
        $fatal(1,"results-only mode accessed output framebuffer");
      if(dut.core_valid)begin
        active_frame=dut.frame_id-1;
        if(active_frame<0 || active_frame>4)$fatal(1,"unexpected core output frame");
        core_pixels[active_frame]=core_pixels[active_frame]+1;
      end
      if(dut.framebuffer_write)begin
        active_frame=dut.frame_id-1;
        if(dut.core_addr!==writes[active_frame])
          $fatal(1,"top output framebuffer rewrite address frame %0d",active_frame);
        reference_pixel=image_y(active_frame,(writes[active_frame]%OW)+1,(writes[active_frame]/OW)+1);
        if(dut.core_pixel!==reference_pixel[7:0])
          $fatal(1,"top output framebuffer pixel frame %0d address %0d",active_frame,writes[active_frame]);
        writes[active_frame]=writes[active_frame]+1;
      end
      if(dut.tx_start)begin
        active_frame=dut.frame_id-1;
        if(core_pixels[active_frame]!=N || writes[active_frame]!=((active_frame==2)?0:N))
          $fatal(1,"top output incomplete processing or framebuffer frame %0d",active_frame);
      end
    end
    previous_rst=dut.rst;previous_state=dut.state;
  end

  // Observe the storage itself as well as its enables. This catches an
  // implementation that accidentally leaves the RAM always block ungated.
  // The preceding packed frame has distinct first/last pixels, so an illicit
  // read when the result sender resets its address changes read_data.
  always @(negedge clk)begin
    if(!dut.rst && dut.features_only)begin
      if(!watching_features)begin
        for(snapshot_index=0;snapshot_index<N;snapshot_index=snapshot_index+1)
          frozen_framebuffer[snapshot_index]=dut.framebuffer[snapshot_index];
        frozen_read_data=dut.read_data;watching_features=1;
        if(frozen_framebuffer[0]===frozen_framebuffer[N-1])
          $fatal(1,"features read-gating fixture needs distinct first/last pixels");
      end else begin
        if(dut.read_data!==frozen_read_data)$fatal(1,"results-only mode changed RAM read register");
        for(snapshot_index=0;snapshot_index<N;snapshot_index=snapshot_index+1)
          if(dut.framebuffer[snapshot_index]!==frozen_framebuffer[snapshot_index])
            $fatal(1,"results-only mode changed framebuffer address %0d",snapshot_index);
      end
    end else watching_features=0;
  end

  // Every requested next mode is changed during acquisition, long before
  // the current UART packet, and must take effect only at the next frame.
  initial begin
    for(control_frame=0;control_frame<5;control_frame=control_frame+1)begin
      @(posedge dut.pattern_active);@(negedge clk);check_controls(control_frame);
      repeat(200)@(negedge clk);
      case(control_frame)
        0:sw=16'h1407; // Packed Sobel, dark target, fast subsequent frames.
        1:sw=16'h1cff; // Results-only wins over packing; bright target, threshold 960.
        2:sw=16'h100d; // Recover a complete grayscale v2 image.
        3:sw=16'h5c07; // Diagnostic page ignores all three output requests.
        4:sw=16'h8001; // Stop a sixth frame after the five-frame wire fixture.
      endcase
      repeat(10)@(negedge clk);check_controls(control_frame);
      wait(!dut.pattern_active);
    end
  end

  initial begin
    for(k=0;k<5;k=k+1)begin writes[k]=0;core_pixels[k]=0;end
    fd=$fopen("top_output_wire.bin","wb");
    if(fd==0)$fatal(1,"cannot open top_output_wire.bin");
    repeat(5)@(negedge clk);btnC=0;
    for(f=0;f<5;f=f+1)begin
      for(i=0;i<32;i=i+1)begin get_byte(received[i]);$fwrite(fd,"%c",received[i]);end
      header_bytes=(f==0)?32:72;
      payload_bytes=(f==2)?0:((f==1)?((N+7)/8):N);
      total=header_bytes+payload_bytes+2;
      for(i=32;i<total;i=i+1)begin get_byte(received[i]);$fwrite(fd,"%c",received[i]);end
      build_reference(f);
      if(u32(0)!==32'h31475046 || received[4]!==((f==0)?8'd1:((f==1 || f==2)?8'd3:8'd2)) ||
         received[5]!==((f==1 || f==2 || f==4)?8'd1:8'd0) ||
         u16(6)!==OW || u16(8)!==OH || u16(10)!==((f==2)?16'd960:16'd160) ||
         u32(12)!==f+1 || u32(16)!==payload_bytes)
        $fatal(1,"top output base header frame %0d",f);
      if(u32(20)!==ref_bright || u32(24)!==ref_bright_x || u32(28)!==ref_bright_y)
        $fatal(1,"top output bright statistics frame %0d",f);
      if(header_bytes==72)begin
        if(received[32]!==((f==1 || f==4)?8'd7:8'd5) || received[33]!==8'd96 ||
           u16(34)!==16'd1 || u16(36)!==16'd1 || u16(38)!==OW || u16(40)!==OH ||
           u16(42)!==ref_x_min || u16(44)!==ref_y_min || u16(46)!==ref_x_max || u16(48)!==ref_y_max ||
           u32(50)!==ref_area || u32(54)!==ref_x || u32(58)!==ref_y ||
           u32(62)!==MIN_AREA || u32(66)!==(N/2) ||
           received[70]!==((f==1)?8'd5:((f==2)?8'd6:8'd0)) || received[71]!==8'd0)
          $fatal(1,"top output target extension frame %0d",f);
      end
      for(i=0;i<payload_bytes;i=i+1)begin
        expected_byte=0;
        if(f==1)begin
          for(j=0;j<8;j=j+1)if(i*8+j<N)begin
            xx=(i*8+j)%OW+1;yy=(i*8+j)/OW+1;
            if(image_y(f,xx,yy)!=0)expected_byte=expected_byte|(1<<j);
          end
        end else begin xx=i%OW+1;yy=i/OW+1;expected_byte=image_y(f,xx,yy);end
        if(received[header_bytes+i]!==expected_byte[7:0])
          $fatal(1,"top output payload frame %0d byte %0d: %0d expected %0d",
            f,i,received[header_bytes+i],expected_byte);
      end
      crc=16'hffff;
      for(i=4;i<total-2;i=i+1)crc=update_crc(crc,received[i]);
      if(u16(total-2)!==crc)$fatal(1,"top output CRC frame %0d",f);
      check_controls(f);
      wait(dut.tx_done);@(negedge clk);
    end
    if(launch_count!=5 || writes[2]!=0 || core_pixels[2]!=N)
      $fatal(1,"top output frame count/results processing");
    // The diagnostic frame disables fast mode for its next wait, even when
    // SW12 remains a diagnostic request at its own frame boundary.
    if(dut.frame_wait_cycles!==FRAME_CYCLES)$fatal(1,"diagnostic page changed frame delay");
    $fclose(fd);
    $display("PASS top output five UART frames: legacy, packed, results, v2 raw, diagnostic; latching, delays, framebuffer gating and rewrite");
    $finish;
  end
  initial begin #5000000;$fatal(1,"top output timeout");end
endmodule
