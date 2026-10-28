`timescale 1ns/1ps
module tb_audit_early_end;
  import video_runtime_pkg::*;
  reg clk=0;always #5 clk=~clk;
  reg rst=1,sv=0,sev=0;reg [63:0] token=0;
  source_end_t ending;frame_config_t config_value;
  wire start,invalid,abort;wire [3:0] reason;
  wire [31:0] seen,accepted,bad,dropped;integer cycle=0,end_cycle=0;
  ingress_guard #(16,16,55,1000,1024) dut(
    .clk(clk),.rst(rst),.source_valid(sv),.source_token(token),
    .source_end_valid(sev),.source_end(ending),.shadow_config(config_value),
    .stop_request(1'b0),.arithmetic_error(1'b0),.core_done_valid(1'b0),
    .core_done_frame_id(32'd0),.core_done_ok(1'b0),
    .core_abort(abort),.frame_start_valid(start),.frame_invalid_valid(invalid),
    .frame_invalid_reason(reason),.seen_frames(seen),.accepted_frames(accepted),
    .invalid_frames(bad),.dropped_source(dropped));
  always @(posedge clk)begin
    cycle=cycle+1;
    if(!rst)begin
      if(sev)begin end_cycle=cycle;$display("SOURCE_END reason7 cycle=%0d state=%0d",cycle,dut.state);end
      if(start)$display("FRAME_START cycle=%0d",cycle);
      if(invalid)begin
        if(reason!=7)$fatal(1,"early source error7 lost: reason=%0d latency=%0d accepted=%0d",reason,cycle-end_cycle,accepted);
        $display("PASS tb_audit_early_end reason7 retained latency=%0d",cycle-end_cycle);$finish;
      end
    end
    if(cycle>300)$fatal(1,"early source error was never reported");
  end
  initial begin
    ending='0;config_value='0;config_value.epsilon=1024;config_value.threshold=2;
    config_value.gain=256;config_value.view_mode=2;
    repeat(3)@(negedge clk);rst=0;
    @(negedge clk);sv=1;token=pack_pixel(8'd77,0,0,1,0,0,42);
    @(negedge clk);sv=0;token=0;sev=1;ending={32'd42,1'b0,4'd7};
    @(negedge clk);sev=0;
  end
endmodule
