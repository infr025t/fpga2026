`timescale 1ns/1ps
// 每拍恢复除法，一次运算32拍；除零返回全1商。
module u32_div(input wire clk,rst,start,input wire [31:0] numerator,denominator,
 output reg busy,done,output reg [31:0] quotient,remainder);
 reg [31:0] q,d; reg [32:0] r; reg [5:0] count;
 wire [32:0] shifted={r[31:0],q[31]};
 wire ge=shifted>={1'b0,d};
 wire [32:0] next_r=ge ? shifted-{1'b0,d}:shifted;
 wire [31:0] next_q={q[30:0],ge};
 always @(posedge clk) begin
  if(rst) begin busy<=0;done<=0;quotient<=0;remainder<=0;q<=0;d<=0;r<=0;count<=0;end
  else begin
   done<=0;
   if(start&&!busy) begin busy<=1;q<=numerator;d<=denominator;r<=0;count<=0;end
   else if(busy) begin
    q<=next_q;r<=next_r;
    if(count==31) begin quotient<=next_q;remainder<=next_r[31:0];busy<=0;done<=1;end
    else count<=count+1'b1;
   end
  end
 end
endmodule
