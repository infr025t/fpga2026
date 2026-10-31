module nt35510_init #(parameter CLK_HZ=100000000)(
 input wire clk,rst,word_ready,word_done,output wire word_valid,output wire[15:0]word,output wire word_rs,lcd_reset_n,init_done);
 assign word_valid=0;assign word=0;assign word_rs=0;assign lcd_reset_n=!rst;assign init_done=!rst;
endmodule
