`timescale 1ns/1ps
// Exercise the real UART path in three concurrent preview configurations.
module tb_top_preview;
  wire done0,done1,done3;
  preview_case #(.INTERVAL(0)) disabled(done0);
  preview_case #(.INTERVAL(1)) every_frame(done1);
  preview_case #(.INTERVAL(3),.RECORD(1)) periodic(done3);
  initial begin
    wait(done0 && done1 && done3);
    $display("PASS top preview intervals 0/1/3, cadence, pause, re-entry, diagnostics, mode/threshold/polarity changes, pixels, target statistics, RAM gating and UART CRC");
    $finish;
  end
  initial begin #10000000;$fatal(1,"preview timeout");end
endmodule

module preview_case #(parameter integer INTERVAL=3,RECORD=0)(output reg finished=0);
  localparam integer W=9,H=6,OW=W-2,OH=H-2,N=OW*OH,CPB=4,FRAMES=13;
  reg clk=0;always #5 clk=~clk;
  reg btn=1;reg[15:0]sw=16'h3805;
  tri1 scl,sda,cam_reset;
  wire tx,rclk,rrst,wen;wire[15:0]led;
  stream_top #(.W(W),.H(H),.UART_DIV(CPB),.START_DELAY(7),
    .FRAME_DELAY(5),.FAST_FRAME_DELAY(2),.TARGET_MIN_AREA(2),
    .CAM_RESET_CYCLES(5),.CAM_SETTLE_CYCLES(7),.PREVIEW_INTERVAL(INTERVAL)) dut(
    .clk100(clk),.btnC(btn),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_sioc(scl),.cam_siod(sda),.cam_rst_n(cam_reset),.cam_rclk(rclk),
    .cam_rrst_n(rrst),.cam_wen(wen),.uart_txd(tx),.led(led));
  reg[7:0]received[0:72+N+1];
  integer writes[0:FRAMES-1];
  integer f,i,j,k,fd,total,payload,version,transport,countdown=0;
  integer x,y,value,expected,area,sx,sy,bx0,by0,bx1,by1,bright,bsx,bsy;
  integer driver_frame;
  reg dark,edge_mode,packed_image,features,preview_enabled,refresh;
  reg[15:0]crc;
  function[15:0] settings(input integer frame);
    begin
      if(frame==4)settings=16'h1805;
      else if(frame==6)settings=16'h7805;
      else if(frame>=12)settings=16'h3c1f;
      else if(frame>=10)settings=16'h3c17;
      else if(frame>=8)settings=16'h3c07;
      else settings=16'h3805;
    end
  endfunction
  function integer source_y(input integer frame,xx,yy);
    reg inside_rect;
    begin
      inside_rect=(xx>=W/4 && xx<W/2 && yy>=H/4 && yy<3*H/4);
      source_y=inside_rect?((frame>=12)?220:32):((frame>=12)?32:220);
    end
  endfunction
  function integer image_y(input integer frame,xx,yy);
    integer gx,gy,mag,th;
    begin
      if(frame<8)image_y=source_y(frame,xx,yy);
      else begin
        gx=source_y(frame,xx+1,yy-1)+2*source_y(frame,xx+1,yy)+source_y(frame,xx+1,yy+1)
          -source_y(frame,xx-1,yy-1)-2*source_y(frame,xx-1,yy)-source_y(frame,xx-1,yy+1);
        gy=source_y(frame,xx-1,yy+1)+2*source_y(frame,xx,yy+1)+source_y(frame,xx+1,yy+1)
          -source_y(frame,xx-1,yy-1)-2*source_y(frame,xx,yy-1)-source_y(frame,xx+1,yy-1);
        mag=(gx<0?-gx:gx)+(gy<0?-gy:gy);th=(frame>=10)?64:160;
        image_y=(mag>=th)?255:0;
      end
    end
  endfunction
  function[31:0]u32(input integer off);
    u32={received[off+3],received[off+2],received[off+1],received[off]};
  endfunction
  function[15:0]u16(input integer off);
    u16={received[off+1],received[off]};
  endfunction
  function[15:0]update_crc(input[15:0]c,input[7:0]b);
    reg[15:0]v;integer n;
    begin v=c^{b,8'b0};for(n=0;n<8;n=n+1)v=v[15]?(v<<1)^16'h1021:v<<1;update_crc=v;end
  endfunction
  task get_byte(output[7:0]b);
    integer bit_index;
    begin
      @(negedge tx);#(CPB*10/2);
      if(tx!==0)$fatal(1,"preview UART start");
      for(bit_index=0;bit_index<8;bit_index=bit_index+1)begin #(CPB*10);b[bit_index]=tx;end
      #(CPB*10);if(tx!==1)$fatal(1,"preview UART stop");
    end
  endtask
  always @(posedge clk)if(!dut.rst)begin
    if(dut.features_only && (dut.framebuffer_write || dut.framebuffer_read))
      $fatal(1,"preview results accessed framebuffer");
    if(dut.framebuffer_write)begin
      if(dut.frame_id<1 || dut.frame_id>FRAMES)$fatal(1,"unexpected preview frame");
      if(dut.core_addr!==writes[dut.frame_id-1])$fatal(1,"preview RAM address");
      if(dut.core_pixel!==image_y(dut.frame_id-1,writes[dut.frame_id-1]%OW+1,writes[dut.frame_id-1]/OW+1))
        $fatal(1,"preview RAM pixel");
      writes[dut.frame_id-1]=writes[dut.frame_id-1]+1;
    end
  end
  // Pause during every acquisition: it must finish with its latched settings.
  initial begin
    for(driver_frame=0;driver_frame<FRAMES;driver_frame=driver_frame+1)begin
      @(posedge dut.pattern_active);repeat(20)@(negedge clk);
      sw=settings(driver_frame)|16'h8000;
      wait(dut.tx_done);@(negedge clk);wait(dut.state==0);
      repeat(30)@(negedge clk);
      if(dut.frame_id!==driver_frame+1)$fatal(1,"pause launched another frame");
      sw=(driver_frame+1<FRAMES)?settings(driver_frame+1):16'h8001;
    end
  end
  initial begin
    for(k=0;k<FRAMES;k=k+1)writes[k]=0;
    if(RECORD)begin fd=$fopen("top_preview_wire.bin","wb");if(!fd)$fatal(1,"preview recording");end
    repeat(5)@(negedge clk);btn=0;
    for(f=0;f<FRAMES;f=f+1)begin
      preview_enabled=(INTERVAL>0 && f!=4 && f!=6);
      refresh=(f==0 || f==5 || f==7 || f==8 || f==10 || f==12);
      if(!preview_enabled || refresh)countdown=0;
      features=(f!=6) && (!preview_enabled || countdown!=0);
      edge_mode=(f>=8);dark=(f<12);packed_image=edge_mode && !features;
      payload=features?0:(packed_image?(N+7)/8:N);
      version=(features || packed_image)?3:2;transport=features?6:(packed_image?5:0);
      total=72+payload+2;
      for(i=0;i<total;i=i+1)begin get_byte(received[i]);if(RECORD)$fwrite(fd,"%c",received[i]);end
      if(u32(0)!==32'h31475046 || received[4]!==version || received[5]!==edge_mode ||
         u16(6)!==OW || u16(8)!==OH || u16(10)!==((f>=10)?64:160) ||
         u32(12)!==f+1 || u32(16)!==payload || received[70]!==transport || received[71]!==0)
        $fatal(1,"preview header interval=%0d frame=%0d",INTERVAL,f);
      area=0;sx=0;sy=0;bright=0;bsx=0;bsy=0;bx0=0;by0=0;bx1=0;by1=0;
      for(y=1;y<=OH;y=y+1)for(x=1;x<=OW;x=x+1)begin
        value=source_y(f,x,y);
        if(value>=128)begin bright=bright+1;bsx=bsx+x;bsy=bsy+y;end
        if(dark?(value<=96):(value>=96))begin
          if(area==0)begin bx0=x;by0=y;bx1=x;by1=y;end
          if(x<bx0)bx0=x;if(x>bx1)bx1=x;if(y<by0)by0=y;if(y>by1)by1=y;
          area=area+1;sx=sx+x;sy=sy+y;
        end
      end
      if(u32(20)!==bright || u32(24)!==bsx || u32(28)!==bsy ||
         received[32]!==((dark)?7:5) || received[33]!==96 ||
         u16(34)!==1 || u16(36)!==1 || u16(38)!==OW || u16(40)!==OH ||
         u16(42)!==bx0 || u16(44)!==by0 || u16(46)!==bx1 || u16(48)!==by1 ||
         u32(50)!==area || u32(54)!==sx || u32(58)!==sy || u32(62)!==2 || u32(66)!==N/2)
        $fatal(1,"preview target statistics interval=%0d frame=%0d",INTERVAL,f);
      for(i=0;i<payload;i=i+1)begin
        expected=0;
        if(packed_image)begin
          for(j=0;j<8;j=j+1)if(i*8+j<N && image_y(f,(i*8+j)%OW+1,(i*8+j)/OW+1)!=0)expected=expected|(1<<j);
        end else expected=image_y(f,i%OW+1,i/OW+1);
        if(received[72+i]!==expected)$fatal(1,"preview UART pixel frame=%0d byte=%0d",f,i);
      end
      crc=16'hffff;for(i=4;i<total-2;i=i+1)crc=update_crc(crc,received[i]);
      if(u16(total-2)!==crc)$fatal(1,"preview CRC");
      if(writes[f]!==((features)?0:N))$fatal(1,"preview incomplete framebuffer");
      wait(dut.tx_done);@(negedge clk);
      if(preview_enabled)countdown=(countdown+1)%INTERVAL;
    end
    if(RECORD)$fclose(fd);
    finished=1;
  end
endmodule
