`timescale 1ns/1ps
module tb_plate_text_overlay;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,enabled=1,frame_start=0,result_event=0;
 reg[7:0]result_status=0;reg[6:0]result_count=0;reg[63:0]result_text=0;
 reg[9:0]x=0;reg[8:0]y=0;reg[7:0]pixel=83;wire[7:0]out_pixel;
 plate_text_overlay dut(.*);
 task tick;begin @(posedge clk);#1;end endtask
 task frame;begin @(negedge clk);frame_start=1;tick();@(negedge clk);frame_start=0;end endtask
 task publish(input[63:0]t,input[6:0]n,input[7:0]s);begin
  @(negedge clk);result_text=t;result_count=n;result_status=s;result_event=1;tick();
  @(negedge clk);result_event=0;
 end endtask
 task check_text(input[63:0]t,input[3:0]n,input bit more);begin
  if(dut.active_text!==t || dut.active_count!==n || dut.active_more!==more)$fatal(1,"text commit mismatch");
 end endtask
 integer i,j;reg[34:0]a;
 initial begin
  tick();@(negedge clk);rst=0;frame();check_text(64'h54494157,4,0);
  publish(64'h35343332314442,7,0);check_text(64'h54494157,4,0);
  frame();check_text(64'h35343332314442,7,0);
  publish(64'h41,1,0);check_text(64'h35343332314442,7,0);frame();check_text(64'h41,1,0);
  // 独立像素期望：A的5x7点阵放大2倍，背景/空白槽/窗口外保持各自定义。
  a=35'b01110_10001_10001_11111_10001_10001_10001;
  for(j=0;j<7;j=j+1)for(i=0;i<5;i=i+1)begin
   x=11+i*2;y=9+j*2;#1;if(out_pixel!==(a[34-j*5-i]?8'hff:8'h00))$fatal(1,"glyph A mismatch");
   x=x+1;y=y+1;#1;if(out_pixel!==(a[34-j*5-i]?8'hff:8'h00))$fatal(1,"scale mismatch");
  end
  x=24;y=12;#1;if(out_pixel!==0)$fatal(1,"short text left stale glyph");
  x=7;y=8;#1;if(out_pixel!==83)$fatal(1,"left outside");
  x=152;y=8;#1;if(out_pixel!==83)$fatal(1,"right outside");
  x=8;y=24;#1;if(out_pixel!==83)$fatal(1,"bottom outside");
  publish(64'h3837363534333231,64,0);frame();check_text(64'h3837363534333231,8,1);
  x=8+8*16+3+4;y=9;#1;if(out_pixel!==255)$fatal(1,"overflow plus absent");
  publish(0,0,0);frame();check_text(64'h454e4f4e,4,0);
  publish(64'h444142,3,1);frame();check_text(64'h525245,3,0);
  @(negedge clk);enabled=0;tick();frame();check_text(64'h46464f,3,0);
  @(negedge clk);enabled=1;tick();frame();check_text(64'h54494157,4,0);
  // 同拍完成与帧开始：整帧显示上一完整结果，下帧才显示新结果。
  @(negedge clk);result_event=1;result_text=64'h42;result_count=1;result_status=0;frame_start=1;tick();
  check_text(64'h54494157,4,0);@(negedge clk);result_event=0;frame_start=0;
  frame();check_text(64'h42,1,0);
  @(negedge clk);rst=1;tick();check_text(64'h54494157,4,0);
  $display("PASS ALL text overlay: atomic updates, modes, glyphs, clipping, overflow, reset");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
