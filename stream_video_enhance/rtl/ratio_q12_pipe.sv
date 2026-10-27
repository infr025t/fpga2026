`timescale 1ns/1ps
module ratio_q12_pipe(
 input wire clk,rst,abort,in_valid,input wire [23:0] v,den,
 output wire out_valid,output wire [11:0] a,output wire range_error);
 localparam integer LATENCY=13;
 reg [13:0] vp,ep;
 reg [23:0] remainder[0:12],denominator[0:12];
 reg [11:0] quotient[0:12];
 wire [24:0] final_double={remainder[12],1'b0};
 wire [12:0] rounded={1'b0,quotient[12]}+(final_double>={1'b0,denominator[12]});
 reg [11:0] result; reg result_error;
 integer k;
 always @(posedge clk) begin
   if(rst || abort)begin vp<=0;ep<=0;result_error<=0;end
   else begin
     vp[0]<=in_valid;
     ep[0]<=in_valid && (den==0 || v>=den || v>24'd10143900 || den>24'd10783900);
     for(k=1;k<=13;k=k+1)begin vp[k]<=vp[k-1];ep[k]<=ep[k-1];end
     result_error<=vp[12] && (ep[12] || rounded>13'd4092);
   end
   remainder[0]<=v;denominator[0]<=den;quotient[0]<=0;
   result<=(ep[12] || rounded>13'd4092) ? 0 : rounded[11:0];
 end
 genvar s;
 generate for(s=1;s<=12;s=s+1)begin:g_bit
   wire [24:0] doubled={remainder[s-1],1'b0};
   wire take=doubled>={1'b0,denominator[s-1]};
   wire [24:0] next_remainder=take ? doubled-{1'b0,denominator[s-1]} : doubled;
   always @(posedge clk)begin
     denominator[s]<=denominator[s-1];
     remainder[s]<=next_remainder[23:0];
     quotient[s]<={quotient[s-1][10:0],take};
   end
 end endgenerate
 assign out_valid=vp[13] && !rst && !abort;
 assign a=result;
 assign range_error=out_valid && result_error;
endmodule
