`timescale 1ns/1ps
// Self-contained budget and 1/8-pixel boundary checks. No large wire artifacts.
module output_budget_case #(
  parameter integer W=318,H=238,CPB=4
)(
  output reg complete=0,
  output reg [31:0] raw_bytes=0,packed_bytes=0,features_bytes=0,
  output reg [31:0] raw_cycles=0,packed_cycles=0,features_cycles=0
);
  localparam integer N=W*H;
  reg clk=0,rst=1,start=0,pack_edges=0,features_only=0;
  always #5 clk=~clk;
  reg [31:0] frame_id=900;
  wire [16:0] addr;
  reg [7:0] rd;
  wire busy,done,tx;
  integer scenario=0,accepted=0,captures=0,cycles=0,expected_bytes=0;
  reg [15:0] crc=16'hffff;
  frame_sender #(.W(W),.H(H),.CLKS_PER_BIT(CPB),.TARGET_PROTOCOL(1),.OUTPUT_PROTOCOL(1)) dut
    (.clk(clk),.rst(rst),.start(start),.edge_mode(1'b1),.threshold(11'd180),
     .frame_id(frame_id),.bright_count(32'd0),.sum_x(32'd0),.sum_y(32'd0),
     .ram_addr(addr),.ram_data(rd),.busy(busy),.done(done),.uart_txd(tx),
     .target_enable(1'b1),.target_valid(1'b0),.target_dark(1'b1),.config_valid(1'b1),
     .target_threshold(8'd64),.roi_x_min(16'd1),.roi_y_min(16'd1),
     .roi_x_max(16'(W)),.roi_y_max(16'(H)),.bbox_x_min(16'd0),.bbox_y_min(16'd0),
     .bbox_x_max(16'd0),.bbox_y_max(16'd0),.target_area(32'd0),.target_sum_x(32'd0),
     .target_sum_y(32'd0),.min_area(32'd1),.max_area(32'(N)),
     .pack_edges(pack_edges),.features_only(features_only));
  function [7:0] memory_byte(input integer index);
    begin memory_byte=(index%3==0 || index==N-1)?8'hff:8'h00; end
  endfunction
  function [15:0] update_crc(input [15:0] c,input [7:0] b);
    reg [15:0] v; integer k;
    begin v=c^{b,8'b0}; for(k=0;k<8;k=k+1)v=v[15]?(v<<1)^16'h1021:v<<1;update_crc=v;end
  endfunction
  function [7:0] expected_byte(input integer index);
    reg [7:0] b;
    integer k,payload_length;
    reg [31:0] val;
    begin
      b=0;val=0;
      payload_length=(scenario==2)?0:((scenario==1)?((N+7)/8):N);
      case(index)
        0:b="F";1:b="P";2:b="G";3:b="1";
        4:b=(scenario==0)?2:3;5:b=1;
        6:b=W&255;7:b=(W>>8)&255;8:b=H&255;9:b=(H>>8)&255;
        10:b=180;32:b=6;33:b=64;
        34:b=1;36:b=1;38:b=W&255;39:b=(W>>8)&255;
        40:b=H&255;41:b=(H>>8)&255;62:b=1;
        70:b=(scenario==0)?0:((scenario==1)?5:6);
        default:begin end
      endcase
      if(index>=12 && index<=15)begin val=900+scenario;b=(val>>(8*(index-12)))&255;end
      if(index>=16 && index<=19)begin val=payload_length;b=(val>>(8*(index-16)))&255;end
      if(index>=66 && index<=69)begin val=N;b=(val>>(8*(index-66)))&255;end
      if(index>=72)begin
        if(scenario==0)b=memory_byte(index-72);
        else begin
          b=0;
          for(k=0;k<8;k=k+1)
            if((index-72)*8+k<N)b[k]=memory_byte((index-72)*8+k)==255;
        end
      end
      expected_byte=b;
    end
  endfunction
  always @(posedge clk)begin
    rd<=memory_byte(addr);
    if(rst || (start && !busy))begin accepted=0;captures=0;cycles=0;crc=16'hffff;end
    else begin
      if(busy)cycles=cycles+1;
      if(dut.state==3)begin
        if(addr!==captures)$fatal(1,"budget N=%0d scenario=%0d RAM address %0d expected %0d",N,scenario,addr,captures);
        captures=captures+1;
      end
      if(dut.valid && dut.ready)begin
        if(accepted<expected_bytes-2)begin
          if(dut.data!==expected_byte(accepted))
            $fatal(1,"budget N=%0d scenario=%0d byte=%0d got=%h expected=%h",N,scenario,accepted,dut.data,expected_byte(accepted));
          if(accepted>=4)crc=update_crc(crc,dut.data);
        end else if(accepted==expected_bytes-2)begin
          if(dut.data!==crc[7:0])$fatal(1,"budget CRC low N=%0d",N);
        end else if(accepted==expected_bytes-1)begin
          if(dut.data!==crc[15:8])$fatal(1,"budget CRC high N=%0d",N);
        end else $fatal(1,"budget excess byte N=%0d",N);
        accepted=accepted+1;
      end
    end
  end
  initial begin
    repeat(5)@(negedge clk);rst=0;
    for(scenario=0;scenario<3;scenario=scenario+1)begin
      pack_edges=(scenario!=0);features_only=(scenario==2);frame_id=900+scenario;
      expected_bytes=74+((scenario==0)?N:((scenario==1)?((N+7)/8):0));
      @(negedge clk);start=1;@(negedge clk);start=0;
      // The bench verifies the complete packet even when requests change live.
      pack_edges=~pack_edges;features_only=~features_only;frame_id=0;
      wait(done);@(negedge clk);
      if(accepted!==expected_bytes)$fatal(1,"budget byte count N=%0d",N);
      if(captures!==((scenario==2)?0:N))$fatal(1,"budget RAM count N=%0d",N);
      if(busy)$fatal(1,"budget busy after done");
      case(scenario)
        0:begin raw_bytes=accepted;raw_cycles=cycles;end
        1:begin packed_bytes=accepted;packed_cycles=cycles;end
        2:begin features_bytes=accepted;features_cycles=cycles;end
      endcase
    end
    if(N>8 && !(features_cycles<packed_cycles && packed_cycles<raw_cycles))
      $fatal(1,"budget cycles did not improve N=%0d",N);
    complete=1;
  end
endmodule

module tb_output_budget;
  wire full_done,one_done,eight_done;
  wire [31:0] raw_bytes,packed_bytes,features_bytes,raw_cycles,packed_cycles,features_cycles;
  integer fd;
  output_budget_case full(.complete(full_done),.raw_bytes(raw_bytes),.packed_bytes(packed_bytes),
    .features_bytes(features_bytes),.raw_cycles(raw_cycles),.packed_cycles(packed_cycles),.features_cycles(features_cycles));
  output_budget_case #(.W(1),.H(1)) single_pixel(.complete(one_done));
  output_budget_case #(.W(8),.H(1)) exact_byte(.complete(eight_done));
  initial begin
    wait(full_done && one_done && eight_done);
    if(raw_bytes!==75758 || packed_bytes!==9535 || features_bytes!==74)$fatal(1,"QVGA byte budget");
    fd=$fopen("output_budget.json","w");
    if(fd==0)$fatal(1,"cannot open output_budget.json");
    $fwrite(fd,"{\n  \"width\": 318, \"height\": 238, \"pixels\": 75684, \"clks_per_bit\": 4,\n");
    $fwrite(fd,"  \"raw\": {\"payload_bytes\": 75684, \"wire_bytes\": %0d, \"cycles\": %0d},\n",raw_bytes,raw_cycles);
    $fwrite(fd,"  \"packed\": {\"payload_bytes\": 9461, \"wire_bytes\": %0d, \"cycles\": %0d},\n",packed_bytes,packed_cycles);
    $fwrite(fd,"  \"features\": {\"payload_bytes\": 0, \"wire_bytes\": %0d, \"cycles\": %0d}\n}\n",features_bytes,features_cycles);
    $fclose(fd);
    $display("PASS output budget QVGA N=75684: raw %0d bytes/%0d cycles, packed %0d bytes/%0d cycles, features %0d bytes/%0d cycles; N=1/N=8 payload, padding, CRC and no-RAM checks",raw_bytes,raw_cycles,packed_bytes,packed_cycles,features_bytes,features_cycles);
    $finish;
  end
  initial begin #100000000;$fatal(1,"output budget timeout");end
endmodule
