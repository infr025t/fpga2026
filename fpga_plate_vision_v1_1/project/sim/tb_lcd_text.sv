`timescale 1ns/1ps
module tb_lcd_text;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,source_valid=0,crop_edge=0,source_done=0,source_error=0;
 reg[7:0]source_pixel=0;reg[9:0]source_x=0;reg[8:0]source_y=0;
 wire roi_event=0,roi_valid=0;wire[7:0]roi_x0=0,roi_y0=0,roi_x1=0,roi_y1=0;
 reg osd_enabled=1,osd_event=0;reg[7:0]osd_status=0;reg[6:0]osd_count=7;
 reg[63:0]osd_text=64'h35343332314442;
 wire ready,busy,done,initialized,background_done;wire[7:0]error;
 wire[31:0]received,painted,input_crc,output_crc,frames;
 wire[7:0]lcd_data;wire lcd_cs_n,lcd_rs,lcd_wr_n,lcd_rd_n,lcd_reset_n,lcd_bl;
 video_lcd_sink #(.CLK_HZ(1000),.BUS_SETUP(2),.BUS_LOW(2),.BUS_HOLD(2),.BUS_GAP(0),.ENABLE_OSD(1)) dut(.*);
 integer index=0,words=0,frame_num=0,fw=640,fh=480;
 reg half_word=0,high_rs=0,monitor_on=0,pixels=0;reg[7:0]hi;reg[15:0]word_value;
 function automatic[34:0]font(input[7:0]ch);
  begin case(ch)
   "B":font=35'b11110_10001_10001_11110_10001_10001_11110;
   "D":font=35'b11110_10001_10001_10001_10001_10001_11110;
   "1":font=35'b00100_01100_00100_00100_00100_00100_01110;
   "2":font=35'b01110_10001_00001_00010_00100_01000_11111;
   "3":font=35'b11110_00001_00001_01110_00001_00001_11110;
   "4":font=35'b00010_00110_01010_10010_11111_00010_00010;
   "5":font=35'b11111_10000_10000_11110_00001_00001_11110;
   "A":font=35'b01110_10001_10001_11111_10001_10001_10001;
   default:font=0;
  endcase end
 endfunction
 function automatic[7:0]expected(input integer xx,yy,fn);
  reg[63:0]txt;reg[34:0]g;integer slot,sx,sy;
  begin
   expected=(xx+3*yy+7)^(xx>>3);
   if(xx>=8&&xx<152&&yy>=8&&yy<24)begin
    expected=0;slot=(xx-8)/16;sx=(xx-8)%16;sy=yy-8;
    txt=fn==0?64'h35343332314442:64'h41;
    if(slot<(fn==0?7:1)&&sx>=3&&sx<13&&sy>=1&&sy<15)begin
     g=font(txt[slot*8+:8]);expected=g[34-((sy-1)/2)*5-(sx-3)/2]?255:0;
    end
   end
  end
 endfunction
 reg[7:0]e;reg[15:0]rgb;integer fd;
 // 从实际WR上升沿重建8位总线的16位字，不能用内部像素握手代替写屏核验。
 always @(posedge lcd_wr_n)if(!rst&&!lcd_cs_n)begin
  if(!half_word)begin hi=lcd_data;high_rs=lcd_rs;half_word=1;end
  else begin
   half_word=0;word_value={hi,lcd_data};
   if(high_rs!==lcd_rs)$fatal(1,"RS changed inside word");
   if(monitor_on)begin
    if(!lcd_rs)begin
     if(word_value==16'h2c00)begin pixels=1;index=0;end
    end else if(pixels)begin
     if(index>=fw*fh)$fatal(1,"extra LCD pixel");
     e=expected(index%fw,index/fw,frame_num);rgb={e[7:3],e[7:2],e[7:3]};
     if(word_value!==rgb)$fatal(1,"LCD mismatch frame=%0d x=%0d y=%0d got=%h want=%h",frame_num,index%fw,index/fw,word_value,rgb);
     if(frame_num==0)$fdisplay(fd,"%04x",word_value);
     index=index+1;words=words+1;
    end
   end
  end
 end
 integer n;
 task run_frame(input bit edge_mode);begin
  crop_edge=edge_mode;fw=edge_mode?630:640;fh=edge_mode?470:480;
  // 先让组合ready响应尺寸切换；否则测试平台会误把模式切换清屏当作新视频帧。
  #1;
  wait(ready);@(negedge clk);monitor_on=1;pixels=0;start=1;
  @(negedge clk);start=0;
  for(n=0;n<fw*fh;n=n+1)begin
   source_valid=1;source_x=n%fw;source_y=n/fw;source_pixel=(source_x+3*source_y+7)^(source_x>>3);
   source_done=n==fw*fh-1;
   // 更新结果发生在第一帧中途，第一帧必须仍完整显示BD12345。
   if(frame_num==0&&n==100)begin osd_text=64'h41;osd_count=1;osd_event=1;end
   @(negedge clk);source_valid=0;source_done=0;osd_event=0;
   repeat((n%19==0)?17:13)@(negedge clk);
  end
  wait(done);#1;
  if(error||index!=fw*fh||received!=fw*fh||painted!=fw*fh||input_crc!==output_crc)$fatal(1,"frame completion/CRC failed");
  monitor_on=0;pixels=0;frame_num=frame_num+1;
 end endtask
 initial begin
  fd=$fopen("lcd_raw_words.hex","w");
  repeat(3)@(negedge clk);rst=0;osd_event=1;@(negedge clk);osd_event=0;
  run_frame(0);run_frame(1);
  $fclose(fd);
  $display("PASS ALL LCD text: %0d RGB565 pixels checked on LCD pins; RAW/EDGE, bubbles, frame atomicity, source CRC preserved",words);$finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
