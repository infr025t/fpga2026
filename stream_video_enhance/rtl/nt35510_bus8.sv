`timescale 1ns/1ps
// Write-only NT35510 MCU-8080 bus for the project's 100 MHz clock.
// A handshake latches one complete 16-bit command/data/pixel word. High byte
// precedes low byte; CS stays selected and RS stays fixed across both strobes.
// A held valid starts another word only after ready is asserted again.
module nt35510_bus8 #(
  parameter integer SETUP_CYCLES=2,LOW_CYCLES=3,HOLD_CYCLES=2,GAP_CYCLES=1
)(
  input wire clk,rst,in_valid,input wire [15:0] in_word,input wire in_rs,
  output wire in_ready,output reg [7:0] lcd_data,
  output reg lcd_cs_n,lcd_rs,lcd_wr_n,output wire lcd_rd_n,output reg word_done
);
  localparam [2:0] IDLE=0,SETUP=1,LOW=2,HOLD=3,GAP=4;
  localparam integer MAX_A=(SETUP_CYCLES>LOW_CYCLES)?SETUP_CYCLES:LOW_CYCLES;
  localparam integer MAX_B=(HOLD_CYCLES>GAP_CYCLES)?HOLD_CYCLES:GAP_CYCLES;
  localparam integer MAX_C=(MAX_A>MAX_B)?MAX_A:MAX_B;
  localparam integer CW=(MAX_C<2)?1:$clog2(MAX_C+1);
  reg [2:0] state;
  reg [CW-1:0] count;
  reg [15:0] latched_word;
  reg second_byte,cs_n,rs,wr_n,done;
  reg [7:0] data;
  assign in_ready=!rst && state==IDLE;
  assign lcd_rd_n=1'b1;
  // Reset makes external strobes inactive even between clock edges. The board
  // wrapper must also reset/reinitialize the panel when cancelling a transfer.
  always @*begin
    lcd_data=rst?8'd0:data;
    lcd_cs_n=rst?1'b1:cs_n;
    lcd_rs=rst?1'b0:rs;
    lcd_wr_n=rst?1'b1:wr_n;
    word_done=rst?1'b0:done;
  end
  initial if(SETUP_CYCLES<2 || LOW_CYCLES<2 || HOLD_CYCLES<1 || GAP_CYCLES<0)
    $fatal(1,"unsafe NT35510 timing parameters for 100 MHz");
  always @(posedge clk or posedge rst)begin
    if(rst)begin
      state<=IDLE;count<=0;latched_word<=0;second_byte<=0;
      data<=0;cs_n<=1;rs<=0;wr_n<=1;done<=0;
    end else begin
      done<=0;
      case(state)
        IDLE:if(in_valid)begin
          latched_word<=in_word;data<=in_word[15:8];rs<=in_rs;
          cs_n<=0;wr_n<=1;second_byte<=0;count<=0;state<=SETUP;
        end
        SETUP:if(count==SETUP_CYCLES-1)begin count<=0;wr_n<=0;state<=LOW;end
          else count<=count+1'b1;
        LOW:if(count==LOW_CYCLES-1)begin count<=0;wr_n<=1;state<=HOLD;end
          else count<=count+1'b1;
        HOLD:if(count==HOLD_CYCLES-1)begin
          count<=0;
          if(!second_byte)begin data<=latched_word[7:0];second_byte<=1;state<=SETUP;end
          else begin cs_n<=1;done<=1;state<=(GAP_CYCLES==0)?IDLE:GAP;end
        end else count<=count+1'b1;
        GAP:if(count==GAP_CYCLES-1)begin count<=0;state<=IDLE;end
          else count<=count+1'b1;
        default:begin state<=IDLE;count<=0;cs_n<=1;wr_n<=1;end
      endcase
    end
  end
endmodule
