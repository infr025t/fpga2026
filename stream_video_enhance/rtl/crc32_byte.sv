`timescale 1ns/1ps
// CRC-32/ISO-HDLC byte update. The caller owns initial/final XORs.
// All eight reflected polynomial steps are combinational: one byte per clock.
module crc32_byte(input wire [31:0] state,input wire [7:0] data,
                  output reg [31:0] next_state);
 integer bit_index;
 always @*begin
   next_state=state^{24'b0,data};
   for(bit_index=0;bit_index<8;bit_index=bit_index+1)
     next_state=next_state[0]?(next_state>>1)^32'hedb88320:next_state>>1;
 end
endmodule
