`timescale 1ns/1ps
module tb_top_target;
  localparam W=16,H=12,OW=W-2,OH=H-2,CPB=4;
  reg clk=0;always #5 clk=~clk;
  reg btnC=1;reg[15:0]sw=1;
  tri1 scl,sda,cam_reset;
  wire tx,rclk,rrst,wen;wire[15:0]led;
  stream_top #(.W(W),.H(H),.UART_DIV(CPB),.START_DELAY(20),
    .CAM_RESET_CYCLES(10),.CAM_SETTLE_CYCLES(12)) dut(
    .clk100(clk),.btnC(btnC),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_rst_n(cam_reset),.cam_sioc(scl),.cam_siod(sda),.cam_rclk(rclk),
    .cam_rrst_n(rrst),.cam_wen(wen),.uart_txd(tx),.led(led));
  reg[7:0]received[0:72+OW*OH+2-1];
  integer fd,f,i,header_bytes,total,expected_pixel,xx,yy;
  reg[15:0]crc;
  function[15:0] update_crc(input[15:0]c,input[7:0]b);
    reg[15:0]v;integer k;
    begin v=c^{b,8'b0};for(k=0;k<8;k=k+1)v=v[15]?(v<<1)^16'h1021:v<<1;update_crc=v;end
  endfunction
  function[31:0]u32(input integer offset);
    u32={received[offset+3],received[offset+2],received[offset+1],received[offset]};
  endfunction
  function[15:0]u16(input integer offset);
    u16={received[offset+1],received[offset]};
  endfunction
  function integer source_y(input integer frame,x,y);
    reg inside_rect;
    begin
      inside_rect=(x>=W/4 && x<W/2 && y>=H/4 && y<3*H/4);
      if(frame==1)source_y=inside_rect?32:220;
      else if(frame==2)source_y=inside_rect?220:32;
      else source_y=inside_rect?220:((x+y)%96);
    end
  endfunction
  function integer image_y(input integer frame,x,y);
    integer gx,gy,mag;
    begin
      if(frame!=2)image_y=source_y(frame,x,y);
      else begin
        gx=source_y(frame,x+1,y-1)+2*source_y(frame,x+1,y)+source_y(frame,x+1,y+1)
          -source_y(frame,x-1,y-1)-2*source_y(frame,x-1,y)-source_y(frame,x-1,y+1);
        gy=source_y(frame,x-1,y+1)+2*source_y(frame,x,y+1)+source_y(frame,x+1,y+1)
          -source_y(frame,x-1,y-1)-2*source_y(frame,x,y-1)-source_y(frame,x+1,y-1);
        mag=(gx<0?-gx:gx)+(gy<0?-gy:gy);
        image_y=(mag>=160)?255:0;
      end
    end
  endfunction
  task get_byte(output[7:0]b);
    integer k;
    begin
      @(negedge tx);#(CPB*10/2);
      if(tx!==0)$fatal(1,"bad start bit");
      for(k=0;k<8;k=k+1)begin #(CPB*10);b[k]=tx;end
      #(CPB*10);if(tx!==1)$fatal(1,"bad stop bit");
    end
  endtask
  initial begin
    fd=$fopen("top_target_wire.bin","wb");
    if(fd==0)$fatal(1,"cannot open top_target_wire.bin");
    repeat(5)@(negedge clk);btnC=0;
    for(f=0;f<4;f=f+1)begin
      for(i=0;i<32;i=i+1)begin get_byte(received[i]);$fwrite(fd,"%c",received[i]);end
      if(u32(0)!==32'h31475046 || u16(6)!=OW || u16(8)!=OH || u32(12)!=f+1)
        $fatal(1,"top base header frame %0d",f);
      if(received[4]!=((f==1 || f==2)?2:1) || received[5]!=(f==2))
        $fatal(1,"top frame-boundary mode/version %0d",f);
      header_bytes=(received[4]==2)?72:32;total=header_bytes+OW*OH+2;
      for(i=32;i<total;i=i+1)begin get_byte(received[i]);$fwrite(fd,"%c",received[i]);end
      if(u32(16)!=OW*OH || u16(10)!=160)$fatal(1,"top dimensions/threshold");
      if(u32(20)!=(f==1?116:24) || u32(24)!=(f==1?918:132) || u32(28)!=(f==1?638:132))
        $fatal(1,"top bright statistics frame %0d",f);
      if(header_bytes==72)begin
        if(received[32]!=(f==1?7:5) || received[33]!=(f==1?96:128))
          $fatal(1,"top target flags/latched threshold %0d",f);
        if(u16(34)!=1 || u16(36)!=1 || u16(38)!=14 || u16(40)!=10 ||
           u16(42)!=4 || u16(44)!=3 || u16(46)!=7 || u16(48)!=8 ||
           u32(50)!=24 || u32(54)!=132 || u32(58)!=132 || u32(62)!=16 || u32(66)!=70 || u16(70)!=0)
          $fatal(1,"top target statistics/config frame %0d",f);
      end
      for(i=0;i<OW*OH;i=i+1)begin
        xx=i%OW+1;yy=i/OW+1;expected_pixel=image_y(f,xx,yy);
        if(received[header_bytes+i]!==expected_pixel[7:0])
          $fatal(1,"top image mismatch frame %0d pixel %0d",f,i);
      end
      crc=16'hffff;
      for(i=4;i<total-2;i=i+1)crc=update_crc(crc,received[i]);
      if(u16(total-2)!==crc)$fatal(1,"top target CRC");
      wait(dut.tx_done);@(negedge clk);
      if(f==0)begin
        sw=16'h0005; // Enable dark-target localization for the next frame.
        wait(dut.pattern_active);repeat(200)@(negedge clk);
        sw=16'h020f; // Change to bright/Sobel/128 during acquisition.
        if(!dut.target_dark || dut.target_threshold!=96 || dut.edge_mode)
          $fatal(1,"switch changes leaked into active target frame");
      end
      if(f==2)sw=1; // Return to byte-for-byte legacy mode at the next boundary.
    end
    $fclose(fd);
    $display("PASS top target four UART frames: legacy, dark, bright/Sobel, legacy; switch latching and pixels");
    $finish;
  end
  initial begin #5000000;$fatal(1,"top target timeout");end
endmodule
