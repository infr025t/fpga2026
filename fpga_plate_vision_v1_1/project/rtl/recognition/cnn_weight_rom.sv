`timescale 1ns/1ps
// 独立同步 ROM 保留推断边界，初始化范围之外的地址填零。
(* keep_hierarchy="yes" *)
module cnn_weight_rom #(parameter FILE="model/weights.hex") (
  input wire clk,
  input wire [14:0] addr,
  output reg [7:0] data
);
  (* rom_style="block", ram_style="block" *) reg [7:0] mem [0:32767];
  integer k;
  initial begin
    for (k=0;k<32768;k=k+1) mem[k]=0;
    $readmemh(FILE,mem,0,28871);
  end
  always @(posedge clk) data<=mem[addr];
endmodule
