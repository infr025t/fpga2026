`timescale 1ns/1ps
module div25_pipe #(parameter integer IN_W=21,OUT_W=16)(
 input wire clk,rst,abort,in_valid,input wire [IN_W-1:0] n,
 output wire out_valid,output wire [OUT_W-1:0] q,output wire range_error);
 localparam integer LATENCY=4;
 initial if(IN_W<1 || IN_W>21 || OUT_W<1 || OUT_W>16)
   $fatal(1,"illegal div25_pipe parameters");
 reg [4:0] vp,ep;
 reg [20:0] n0,n1,n2,n3;
 // 671089 = 15729 + 20*32768. Keep the merged product at U41.
 reg [35:0] lo1; reg [25:0] hi1;
 reg [40:0] product2;
 reg [16:0] q3;
 wire [21:0] q25=({5'b0,q3}<<4)+({5'b0,q3}<<3)+{5'b0,q3};
 wire [16:0] corrected=q3-(q25>{1'b0,n3});
 wire overflow_q=corrected > ((17'd1<<OUT_W)-1);
 reg [OUT_W-1:0] result;
 reg result_error;
 integer k;
 always @(posedge clk) begin
   if(rst || abort)begin vp<=0;ep<=0;result_error<=0;end
   else begin
     vp[0]<=in_valid; ep[0]<=in_valid && (n>21'd1632012);
     for(k=1;k<=4;k=k+1) begin vp[k]<=vp[k-1];ep[k]<=ep[k-1];end
     result_error<=vp[3] && (ep[3] || overflow_q);
   end
   n0<=n;n1<=n0;n2<=n1;n3<=n2;
   lo1<=n0*15'd15729;
   hi1<=n0*5'd20;
   product2<={5'b0,lo1}+({15'b0,hi1}<<15);
   q3<=product2[40:24];
   result<=(ep[3] || overflow_q) ? 0 : corrected[OUT_W-1:0];
 end
 assign out_valid=vp[4] && !rst && !abort;
 assign q=result;
 assign range_error=out_valid && result_error;
endmodule
