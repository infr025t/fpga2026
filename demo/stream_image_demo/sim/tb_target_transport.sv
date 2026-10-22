`timescale 1ns/1ps
module tb_target_transport;
  localparam W=4,H=2,CPB=4,MAX_N=72+W*H+2;
  reg clk=0,rst=1,start=0,mode=1;
  always #5 clk=~clk;
  reg [10:0] threshold;
  reg [31:0] frame_id,bc,sx,sy;
  reg target_enable,target_valid,target_dark,config_valid;
  reg [7:0] target_threshold;
  reg [15:0] roi_x_min,roi_y_min,roi_x_max,roi_y_max;
  reg [15:0] bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max;
  reg [31:0] target_area,target_sum_x,target_sum_y,min_area,max_area;
  wire [16:0] addr;
  reg [7:0] rd;
  wire busy,done,tx;
  reg [7:0] mem[0:W*H-1],received[0:MAX_N-1],expected[0:71];
  integer fd,i,f,header_bytes,total;
  reg [15:0] crc;
  frame_sender #(.W(W),.H(H),.CLKS_PER_BIT(CPB),.TARGET_PROTOCOL(1)) dut
    (.clk(clk),.rst(rst),.start(start),.edge_mode(mode),.threshold(threshold),
     .frame_id(frame_id),.bright_count(bc),.sum_x(sx),.sum_y(sy),
     .ram_addr(addr),.ram_data(rd),.busy(busy),.done(done),.uart_txd(tx),
     .target_enable(target_enable),.target_valid(target_valid),
     .target_dark(target_dark),.config_valid(config_valid),
     .target_threshold(target_threshold),.roi_x_min(roi_x_min),.roi_y_min(roi_y_min),
     .roi_x_max(roi_x_max),.roi_y_max(roi_y_max),.bbox_x_min(bbox_x_min),
     .bbox_y_min(bbox_y_min),.bbox_x_max(bbox_x_max),.bbox_y_max(bbox_y_max),
     .target_area(target_area),.target_sum_x(target_sum_x),.target_sum_y(target_sum_y),
     .min_area(min_area),.max_area(max_area));
  always @(posedge clk) rd<=mem[addr];

  function [15:0] update_crc(input [15:0] c,input [7:0] b);
    reg [15:0] v; integer k;
    begin v=c^{b,8'b0}; for(k=0;k<8;k=k+1) v=v[15]?(v<<1)^16'h1021:v<<1; update_crc=v; end
  endfunction
  task put_u16(input integer offset,input [15:0] value);
    begin expected[offset]=value[7:0];expected[offset+1]=value[15:8];end
  endtask
  task put_u32(input integer offset,input [31:0] value);
    integer k;
    begin for(k=0;k<4;k=k+1)expected[offset+k]=(value>>(8*k))&8'hff;end
  endtask
  task get_byte(output [7:0] b);
    integer k;
    begin
      @(negedge tx); #(CPB*10/2);
      if(tx!==0) $fatal(1,"bad start bit");
      for(k=0;k<8;k=k+1) begin #(CPB*10); b[k]=tx; end
      #(CPB*10); if(tx!==1) $fatal(1,"bad stop bit");
    end
  endtask
  task configure_frame(input integer frame);
    begin
      mode=frame[0];threshold=11'h5ab+frame;frame_id=32'h10203040+frame;
      bc=4;sx=10;sy=8;
      target_enable=1;target_valid=0;target_dark=1;config_valid=1;
      target_threshold=64;roi_x_min=1;roi_y_min=1;roi_x_max=W;roi_y_max=H;
      bbox_x_min=0;bbox_y_min=0;bbox_x_max=0;bbox_y_max=0;
      target_area=0;target_sum_x=0;target_sum_y=0;min_area=1;max_area=6;
      case(frame)
        0:begin // Valid dark target, in original sensor coordinates.
          target_valid=1;target_area=2;target_sum_x=3;target_sum_y=2;
          bbox_x_min=1;bbox_y_min=1;bbox_x_max=2;bbox_y_max=1;
        end
        1:begin // Valid bright configuration, with no matching target.
          target_dark=0;target_threshold=250;roi_x_min=2;
        end
        2:begin // Invalid configuration retains raw settings, zero statistics.
          config_valid=0;target_threshold=173;
          roi_x_min=16'h0102;roi_y_min=16'h0203;
          min_area=32'h00030004;max_area=32'h00020003;
        end
        3:begin // Geometry remains available when minimum-area filtering fails.
          target_threshold=96;target_area=1;target_sum_x=2;target_sum_y=1;
          bbox_x_min=2;bbox_y_min=1;bbox_x_max=2;bbox_y_max=1;min_area=2;
        end
        4:begin // Return to legacy format after four extended headers.
          target_enable=0;target_valid=1;target_area=2;target_sum_x=3;target_sum_y=2;
          bbox_x_min=1;bbox_y_min=1;bbox_x_max=2;bbox_y_max=1;
        end
        5:begin // Re-enable v2, preserving statistics above the maximum area.
          target_dark=0;target_threshold=128;target_area=8;target_sum_x=20;target_sum_y=12;
          bbox_x_min=1;bbox_y_min=1;bbox_x_max=W;bbox_y_max=H;
        end
      endcase
    end
  endtask
  task make_expected;
    integer k;
    begin
      for(k=0;k<72;k=k+1)expected[k]=0;
      expected[0]="F";expected[1]="P";expected[2]="G";expected[3]="1";
      expected[4]=target_enable?2:1;expected[5]=mode;
      put_u16(6,W);put_u16(8,H);put_u16(10,{5'b0,threshold});
      put_u32(12,frame_id);put_u32(16,W*H);put_u32(20,bc);put_u32(24,sx);put_u32(28,sy);
      expected[32]={5'b0,config_valid,target_dark,target_valid};expected[33]=target_threshold;
      put_u16(34,roi_x_min);put_u16(36,roi_y_min);put_u16(38,roi_x_max);put_u16(40,roi_y_max);
      put_u16(42,bbox_x_min);put_u16(44,bbox_y_min);put_u16(46,bbox_x_max);put_u16(48,bbox_y_max);
      put_u32(50,target_area);put_u32(54,target_sum_x);put_u32(58,target_sum_y);
      put_u32(62,min_area);put_u32(66,max_area);put_u16(70,0);
    end
  endtask
  task mutate_live_inputs;
    begin
      mode=~mode;threshold=0;frame_id=32'hdeadbeef;bc=0;sx=0;sy=0;
      target_enable=~target_enable;target_valid=~target_valid;
      target_dark=~target_dark;config_valid=~config_valid;target_threshold=~target_threshold;
      roi_x_min=~roi_x_min;roi_y_min=~roi_y_min;roi_x_max=~roi_x_max;roi_y_max=~roi_y_max;
      bbox_x_min=~bbox_x_min;bbox_y_min=~bbox_y_min;bbox_x_max=~bbox_x_max;bbox_y_max=~bbox_y_max;
      target_area=~target_area;target_sum_x=~target_sum_x;target_sum_y=~target_sum_y;
      min_area=~min_area;max_area=~max_area;
    end
  endtask
  initial begin
    fd=$fopen("target_wire.bin","wb");
    if(fd==0)$fatal(1,"cannot open target_wire.bin");
    for(i=0;i<W*H;i=i+1)mem[i]=i*31+5;
    repeat(5)@(negedge clk);rst=0;
    for(f=0;f<6;f=f+1)begin
      configure_frame(f);make_expected();
      header_bytes=(f==4)?32:72;total=header_bytes+W*H+2;
      @(negedge clk);start=1;
      @(negedge clk);start=0;mutate_live_inputs();
      for(i=0;i<total;i=i+1)begin get_byte(received[i]);$fwrite(fd,"%c",received[i]);end
      for(i=0;i<header_bytes;i=i+1)
        if(received[i]!==expected[i])
          $fatal(1,"target header frame %0d byte %0d got %h expected %h",f,i,received[i],expected[i]);
      for(i=0;i<W*H;i=i+1)
        if(received[header_bytes+i]!==mem[i])$fatal(1,"target frame %0d pixel %0d",f,i);
      crc=16'hffff;
      for(i=4;i<total-2;i=i+1)crc=update_crc(crc,received[i]);
      if({received[total-1],received[total-2]}!==crc)$fatal(1,"target frame %0d CRC",f);
      wait(done);@(negedge clk);
      if(busy)$fatal(1,"target busy after done");
    end
    $fclose(fd);
    $display("PASS target transport six frames: valid, absent, invalid config, area filters, v1/v2 transition; all metadata latched");
    $finish;
  end
  initial begin #1000000;$fatal(1,"target transport timeout");end
endmodule
