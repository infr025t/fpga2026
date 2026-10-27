`timescale 1ns/1ps
// Sequenced 16-bit command/data words; the separate 8-bit PHY splits each word.
// Delays are explicit conservative policy, not the vendor's software-loop units.
module nt35510_init #(
  parameter integer CLK_HZ=100000000,RESET_LOW_MS=20,RESET_WAIT_MS=120,SLEEP_WAIT_MS=120
)(
  input wire clk,rst,word_ready,word_done,
  output wire word_valid,output wire [15:0] word,output wire word_rs,
  output wire lcd_reset_n,init_done
);
  // Make the multiplication wide BEFORE evaluating CLK_HZ*milliseconds.
  localparam [63:0] RESET_LOW_CYCLES=(64'd1*CLK_HZ*RESET_LOW_MS+64'd999)/64'd1000;
  localparam [63:0] RESET_WAIT_CYCLES=(64'd1*CLK_HZ*RESET_WAIT_MS+64'd999)/64'd1000;
  localparam [63:0] SLEEP_WAIT_CYCLES=(64'd1*CLK_HZ*SLEEP_WAIT_MS+64'd999)/64'd1000;
  localparam [63:0] LONG_RESET=(RESET_LOW_CYCLES>RESET_WAIT_CYCLES)?RESET_LOW_CYCLES:RESET_WAIT_CYCLES;
  localparam [63:0] LONG_WAIT=(LONG_RESET>SLEEP_WAIT_CYCLES)?LONG_RESET:SLEEP_WAIT_CYCLES;
  localparam integer TW=(LONG_WAIT<2)?1:$clog2(LONG_WAIT);
  localparam LOW_RESET=0,RELEASE_WAIT=1,SEND=2,WAIT_DONE=3,SLEEP_WAIT=4,COMPLETE=5;
  reg [2:0] state;
  reg [TW-1:0] timer;
  reg [8:0] index;
  reg data_phase,reset_released;
  wire [15:0] command,data;
  wire has_data,sleep_wait,last;
  nt35510_init_rom rom(.index(index),.command(command),.data(data),
    .has_data(has_data),.sleep_wait(sleep_wait),.last(last));
  assign word_valid=!rst && state==SEND;
  assign word=data_phase?data:command;
  assign word_rs=data_phase;
  // A dedicated pin register avoids a reset glitch from multibit FSM decoding.
  assign lcd_reset_n=!rst && reset_released;
  assign init_done=!rst && state==COMPLETE;
  wire transfer_done=(state==SEND && word_ready && word_done) || (state==WAIT_DONE && word_done);
  initial if(CLK_HZ<1 || RESET_LOW_MS<1 || RESET_WAIT_MS<1 || SLEEP_WAIT_MS<1)
    $fatal(1,"illegal NT35510 initialization delay parameters");
  always @(posedge clk or posedge rst)begin
    if(rst)begin state<=LOW_RESET;timer<=0;index<=0;data_phase<=0;reset_released<=0;end
    else begin
      case(state)
        LOW_RESET:if(timer==RESET_LOW_CYCLES-1)begin timer<=0;reset_released<=1;state<=RELEASE_WAIT;end
          else timer<=timer+1'b1;
        RELEASE_WAIT:if(timer==RESET_WAIT_CYCLES-1)begin timer<=0;state<=SEND;end
          else timer<=timer+1'b1;
        SEND:if(word_ready)state<=WAIT_DONE;
        WAIT_DONE:begin end
        SLEEP_WAIT:if(timer==SLEEP_WAIT_CYCLES-1)begin timer<=0;state<=SEND;end
          else timer<=timer+1'b1;
        COMPLETE:begin end
        default:begin state<=LOW_RESET;timer<=0;index<=0;data_phase<=0;reset_released<=0;end
      endcase
      if(transfer_done)begin
        if(!data_phase && has_data)begin data_phase<=1;state<=SEND;end
        else begin
          data_phase<=0;
          if(last)state<=COMPLETE;
          else begin
            index<=index+1'b1;
            if(sleep_wait)begin timer<=0;state<=SLEEP_WAIT;end
            else state<=SEND;
          end
        end
      end
    end
  end
endmodule
