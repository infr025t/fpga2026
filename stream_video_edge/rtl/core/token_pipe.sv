`timescale 1ns/1ps
// Edge t acceptance -> output at edge t+LATENCY, including bubbles.
module token_pipe #(parameter integer WIDTH=1, LATENCY=0)(
 input wire clk,rst,abort,in_valid,input wire [WIDTH-1:0] in_data,
 output wire out_valid,output wire [WIDTH-1:0] out_data);
 initial if(WIDTH<1 || LATENCY<0) $fatal(1,"illegal token_pipe parameters");
 generate if(LATENCY==0) begin:g_wire
   assign out_valid=in_valid && !rst && !abort;
   assign out_data=out_valid ? in_data : {WIDTH{1'b0}};
 end else begin:g_pipe
   reg [LATENCY:0] valid_pipe;
   reg [WIDTH-1:0] data_pipe[0:LATENCY];
   integer k;
   always @(posedge clk) begin
     if(rst || abort) valid_pipe<=0;
     else begin
       valid_pipe[0]<=in_valid;
       for(k=1;k<=LATENCY;k=k+1)valid_pipe[k]<=valid_pipe[k-1];
     end
     data_pipe[0]<=in_data;
     for(k=1;k<=LATENCY;k=k+1)data_pipe[k]<=data_pipe[k-1];
   end
   assign out_valid=valid_pipe[LATENCY] && !rst && !abort;
   assign out_data=data_pipe[LATENCY];
 end endgenerate
endmodule
