`timescale 1ns/1ps
// This wire stream intentionally contains exactly six packets for PC cross-checks.
module tb_output_transport;
  localparam W=5,H=3,CPB=4,PIXELS=W*H,MAX_N=72+PIXELS+2;
  reg clk=0,rst=1,start=0,mode=1,pack_edges=0,features_only=0;
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
  reg [7:0] mem[0:PIXELS-1],received[0:MAX_N-1],expected[0:MAX_N-1];
  integer fd,i,f,header_bytes,payload_bytes,total,ram_captures;
  reg [15:0] crc;
  reg expected_packed,expected_features;
  frame_sender #(.W(W),.H(H),.CLKS_PER_BIT(CPB),.TARGET_PROTOCOL(1),.OUTPUT_PROTOCOL(1)) dut
    (.clk(clk),.rst(rst),.start(start),.edge_mode(mode),.threshold(threshold),
     .frame_id(frame_id),.bright_count(bc),.sum_x(sx),.sum_y(sy),
     .ram_addr(addr),.ram_data(rd),.busy(busy),.done(done),.uart_txd(tx),
     .target_enable(target_enable),.target_valid(target_valid),
     .target_dark(target_dark),.config_valid(config_valid),
     .target_threshold(target_threshold),.roi_x_min(roi_x_min),.roi_y_min(roi_y_min),
     .roi_x_max(roi_x_max),.roi_y_max(roi_y_max),.bbox_x_min(bbox_x_min),
     .bbox_y_min(bbox_y_min),.bbox_x_max(bbox_x_max),.bbox_y_max(bbox_y_max),
     .target_area(target_area),.target_sum_x(target_sum_x),.target_sum_y(target_sum_y),
     .min_area(min_area),.max_area(max_area),.pack_edges(pack_edges),.features_only(features_only));
  always @(posedge clk) begin
    rd<=mem[addr];
    if(rst || (start && !busy)) ram_captures<=0;
    else if(dut.state==3) begin
      if(addr!==ram_captures) $fatal(1,"RAM sequence frame %0d got %0d expected %0d",f,addr,ram_captures);
      ram_captures<=ram_captures+1;
    end
  end
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
    integer k;
    begin
      mode=1;pack_edges=1;features_only=0;threshold=180+frame;frame_id=100+frame;
      bc=8;sx=21;sy=17;
      target_enable=1;target_valid=1;target_dark=1;config_valid=1;
      target_threshold=64;roi_x_min=1;roi_y_min=1;roi_x_max=W;roi_y_max=H;
      bbox_x_min=2;bbox_y_min=1;bbox_x_max=3;bbox_y_max=2;
      target_area=4;target_sum_x=10;target_sum_y=6;min_area=1;max_area=PIXELS;
      for(k=0;k<PIXELS;k=k+1)mem[k]=((k+frame)%3==0 || k==PIXELS-1)?255:0;
      case(frame)
        0:target_enable=0;
        1:begin end
        2:features_only=1; // Both requests asserted: features must win.
        3:begin
          features_only=1;pack_edges=0;mode=0;target_valid=0;
          target_area=0;target_sum_x=0;target_sum_y=0;
          bbox_x_min=0;bbox_y_min=0;bbox_x_max=0;bbox_y_max=0;
        end
        4:begin // Ineligible requests must fall back to v1 grayscale.
          mode=0;target_enable=0;features_only=1;
          for(k=0;k<PIXELS;k=k+1)mem[k]=k*13+5;
        end
        5:begin // Return from result mode to a complete v2 raw frame.
          pack_edges=0;
          for(k=0;k<PIXELS;k=k+1)mem[k]=k*11+7;
        end
      endcase
    end
  endtask
  task make_expected;
    integer k;
    begin
      expected_features=target_enable && features_only;
      expected_packed=pack_edges && mode && !expected_features;
      header_bytes=(target_enable || expected_packed)?72:32;
      payload_bytes=expected_features?0:(expected_packed?((PIXELS+7)/8):PIXELS);
      total=header_bytes+payload_bytes+2;
      for(k=0;k<MAX_N;k=k+1)expected[k]=0;
      expected[0]="F";expected[1]="P";expected[2]="G";expected[3]="1";
      expected[4]=(expected_features || expected_packed)?3:(target_enable?2:1);expected[5]=mode;
      put_u16(6,W);put_u16(8,H);put_u16(10,{5'b0,threshold});
      put_u32(12,frame_id);put_u32(16,payload_bytes);put_u32(20,bc);put_u32(24,sx);put_u32(28,sy);
      if(target_enable)begin
        expected[32]={5'b0,config_valid,target_dark,target_valid};expected[33]=target_threshold;
        put_u16(34,roi_x_min);put_u16(36,roi_y_min);put_u16(38,roi_x_max);put_u16(40,roi_y_max);
        put_u16(42,bbox_x_min);put_u16(44,bbox_y_min);put_u16(46,bbox_x_max);put_u16(48,bbox_y_max);
        put_u32(50,target_area);put_u32(54,target_sum_x);put_u32(58,target_sum_y);
        put_u32(62,min_area);put_u32(66,max_area);
      end
      if(header_bytes==72)expected[70]=expected_features?6:(expected_packed?(target_enable?5:1):0);
      if(expected_packed)begin
        for(k=0;k<PIXELS;k=k+1)expected[header_bytes+k/8][k%8]=mem[k][7];
      end else if(!expected_features)begin
        for(k=0;k<PIXELS;k=k+1)expected[header_bytes+k]=mem[k];
      end
      crc=16'hffff;
      for(k=4;k<total-2;k=k+1)crc=update_crc(crc,expected[k]);
      expected[total-2]=crc[7:0];expected[total-1]=crc[15:8];
    end
  endtask
  task mutate_live_inputs;
    begin
      mode=~mode;pack_edges=~pack_edges;features_only=~features_only;
      threshold=0;frame_id=32'hdeadbeef;bc=0;sx=0;sy=0;
      target_enable=~target_enable;target_valid=~target_valid;
      target_dark=~target_dark;config_valid=~config_valid;target_threshold=~target_threshold;
      roi_x_min=~roi_x_min;roi_y_min=~roi_y_min;roi_x_max=~roi_x_max;roi_y_max=~roi_y_max;
      bbox_x_min=~bbox_x_min;bbox_y_min=~bbox_y_min;bbox_x_max=~bbox_x_max;bbox_y_max=~bbox_y_max;
      target_area=~target_area;target_sum_x=~target_sum_x;target_sum_y=~target_sum_y;
      min_area=~min_area;max_area=~max_area;
    end
  endtask
  initial begin
    fd=$fopen("output_wire.bin","wb");
    if(fd==0)$fatal(1,"cannot open output_wire.bin");
    // Abort a packet before recording, then prove reset returns UART and FSM idle.
    repeat(5)@(negedge clk);rst=0;configure_frame(0);
    start=1;@(negedge clk);start=0;repeat(12)@(negedge clk);
    rst=1;repeat(3)@(negedge clk);
    if(busy || tx!==1 || done)$fatal(1,"reset did not clear active packet");
    rst=0;
    for(f=0;f<6;f=f+1)begin
      configure_frame(f);make_expected();
      @(negedge clk);start=1;
      @(negedge clk);start=0;mutate_live_inputs();
      for(i=0;i<total;i=i+1)begin get_byte(received[i]);$fwrite(fd,"%c",received[i]);end
      for(i=0;i<total;i=i+1)
        if(received[i]!==expected[i])
          $fatal(1,"output frame %0d byte %0d got %h expected %h",f,i,received[i],expected[i]);
      wait(done);@(negedge clk);
      if(busy)$fatal(1,"busy after done");
      if(ram_captures!==(expected_features?0:PIXELS))$fatal(1,"RAM count frame %0d: %0d",f,ram_captures);
    end
    $fclose(fd);
    $display("PASS output transport six frames: packed LSB/tail, target/no target, features priority, fallbacks, reset, latching, RAM sequence, UART and CRC");
    $finish;
  end
  initial begin #1000000;$fatal(1,"output transport timeout");end
endmodule
