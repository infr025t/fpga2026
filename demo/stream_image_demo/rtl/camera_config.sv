`timescale 1ns/1ps
// Original SCCB write sequencer. Open-drain SIOC/SIOD need external pullups.
// 100 MHz / (4*250) = 100 kHz. No clock-stretch support (OV7670 SCCB).
// SCCB's ninth bit is formally don't-care; this module checks the ACK that
// common OV7670 modules provide. Set CHECK_ACK=0 only after scope diagnosis.
module camera_config #(
  parameter integer QUARTER_CYCLES=250,POWER_WAIT=10000000,REG_WAIT=100000,
  parameter integer CHECK_ACK=1,DIRECT_IO=1
)(input wire clk,rst,inout wire sioc,siod,output reg done,error,
  output wire scl_drive_low,sda_drive_low);
  reg scl_low,sda_low,ack_failed;
  assign sioc=(DIRECT_IO && scl_low)?1'b0:1'bz;
  assign siod=(DIRECT_IO && sda_low)?1'b0:1'bz;
  assign scl_drive_low=scl_low;
  assign sda_drive_low=sda_low;
  reg[31:0]divider,wait_count;
  reg[5:0]index;
  reg[3:0]state,bit_pos;
  reg[1:0]byte_pos;
  reg[23:0]word_data;
  localparam WAITING=0,START=1,BIT_LOW=2,BIT_RISE=3,BIT_HIGH=4,BIT_FALL=5,
    STOP_LOW=6,STOP_RISE=7,STOP_RELEASE=8,NEXT_REG=9,FINISHED=10,FAILED=11;
  localparam REG_COUNT=39;
  // QVGA through 2x DCW from VGA, UYVY (Y is second byte), full-range Y.
  // Keep PCLK running in horizontal blanking for AL422B refresh.
  function automatic [15:0] setting(input [5:0]n);
    case(n)
      0:setting=16'h1280; // software reset; wait 100 ms afterward
      1:setting=16'h1101; // input clock /2, module oscillator 12 or 24 MHz
      2:setting=16'h6b0a; // PLL bypass
      3:setting=16'h1200; // YUV, VGA window before DCW
      4:setting=16'h0c04; // enable downsampling
      5:setting=16'h3e19; // DCW + PCLK divide
      6:setting=16'h703a;
      7:setting=16'h7135;
      8:setting=16'h7211; // horizontal and vertical /2
      9:setting=16'h73f1;
     10:setting=16'ha202;
     11:setting=16'h1716; // window high and low bits must be a matched set
     12:setting=16'h1804;
     13:setting=16'h3224;
     14:setting=16'h1902;
     15:setting=16'h1a7a;
     16:setting=16'h030a;
     17:setting=16'h1502; // negative VSYNC, normal HREF, continuous PCLK
     18:setting=16'h3a0c; // TSLB bit3=1: UYVY, Y_BYTE=1 (bit2 is reserved)
     19:setting=16'h3dc0; // gamma + UV saturation, no UV swap
     20:setting=16'h40c0; // Y output 0..255
     21:setting=16'h8c00; // RGB444 disabled
     22:setting=16'h0400;
     23:setting=16'h1e00; // no mirror/flip
     24:setting=16'h13e7; // auto exposure/gain/white balance
     25:setting=16'h1438;
     26:setting=16'h3b0a;
     27:setting=16'h4f80;
     28:setting=16'h5080;
     29:setting=16'h5100;
     30:setting=16'h5222;
     31:setting=16'h535e;
     32:setting=16'h5480;
     33:setting=16'h589e;
     34:setting=16'h5500; // neutral brightness
     35:setting=16'h5640;
     36:setting=16'h4108;
     37:setting=16'h5500;
     38:setting=16'h4200; // color bars disabled
     default:setting=16'hffff;
    endcase
  endfunction
  always @(posedge clk) begin
    if(rst)begin
      scl_low<=0;sda_low<=0;done<=0;error<=0;ack_failed<=0;divider<=0;
      wait_count<=POWER_WAIT;index<=0;state<=WAITING;
      bit_pos<=0;byte_pos<=0;word_data<=0;
    end else if(state==WAITING)begin
      if(wait_count!=0)wait_count<=wait_count-1;
      else begin word_data<={8'h42,setting(index)};state<=START;divider<=0;end
    end else if(divider!=QUARTER_CYCLES-1)divider<=divider+1;
    else begin
      divider<=0;
      case(state)
        START:begin scl_low<=0;sda_low<=1;byte_pos<=0;bit_pos<=0;state<=BIT_LOW;end
        BIT_LOW:begin scl_low<=1;sda_low<=(bit_pos==8)?0:~word_data[23];state<=BIT_RISE;end
        BIT_RISE:begin scl_low<=0;state<=BIT_HIGH;end
        BIT_HIGH:begin
          if(bit_pos==8 && CHECK_ACK && siod!=1'b0)ack_failed<=1;
          state<=BIT_FALL;
        end
        BIT_FALL:begin
          scl_low<=1;
          if(bit_pos==8)begin
            bit_pos<=0;
            if(byte_pos==2)state<=STOP_LOW;
            else begin byte_pos<=byte_pos+1'b1;state<=BIT_LOW;end
          end else begin bit_pos<=bit_pos+1'b1;word_data<=word_data<<1;state<=BIT_LOW;end
        end
        STOP_LOW:begin scl_low<=1;sda_low<=1;state<=STOP_RISE;end
        STOP_RISE:begin scl_low<=0;state<=STOP_RELEASE;end
        STOP_RELEASE:begin sda_low<=0;state<=NEXT_REG;end
        // Publish failure only after STOP releases the bus. The top level may
        // then reset and retry even with a short retry delay.
        NEXT_REG:if(ack_failed)begin error<=1;state<=FAILED;end
          else if(index==REG_COUNT-1)begin done<=1;state<=FINISHED;end
          else begin index<=index+1'b1;wait_count<=(index==0)?POWER_WAIT:REG_WAIT;state<=WAITING;end
        FINISHED:done<=1;
        FAILED:begin scl_low<=0;sda_low<=0;end
        default:state<=WAITING;
      endcase
    end
  end
endmodule

// Passive register diagnostic after camera_config releases the SCCB bus.
// Two STOP-separated transactions per read: 42,register; then 43,read,NACK.
// Byte lanes in values: PID(0A), COM10(15), TSLB(3A), COM7(12).
// ACK failure is latched; values are not trustworthy when error=1.
module camera_readback #(parameter integer QUARTER_CYCLES=250,DIRECT_IO=1)(
  input wire clk,rst,enable,inout wire sioc,siod,
  output reg done,error,output reg[31:0]values,
  output wire scl_drive_low,sda_drive_low);
  localparam IDLE=0,GAP=1,START=2,TX_LOW=3,TX_RISE=4,TX_SAMPLE=5,TX_FALL=6,
    RX_LOW=7,RX_RISE=8,RX_SAMPLE=9,RX_FALL=10,
    STOP_LOW=11,STOP_RISE=12,STOP_RELEASE=13,NEXT=14,FINISHED=15;
  reg[3:0]state,bit_index;
  reg[31:0]divider;
  reg[1:0]index,gap_count;
  reg read_pass,second_byte,scl_low,sda_low;
  reg[15:0]tx_word;
  reg[7:0]rx_byte;
  assign sioc=(DIRECT_IO && scl_low)?1'b0:1'bz;
  assign siod=(DIRECT_IO && sda_low)?1'b0:1'bz;
  assign scl_drive_low=scl_low;
  assign sda_drive_low=sda_low;
  function automatic[7:0]address(input[1:0]n);
    case(n)0:address=8'h0a;1:address=8'h15;2:address=8'h3a;3:address=8'h12;endcase
  endfunction
  always @(posedge clk)begin
    if(rst)begin
      state<=IDLE;divider<=0;index<=0;gap_count<=0;bit_index<=0;
      read_pass<=0;second_byte<=0;scl_low<=0;sda_low<=0;
      tx_word<=0;rx_byte<=0;done<=0;error<=0;values<=0;
    end else if(state==IDLE)begin
      if(enable)begin state<=GAP;tx_word<=16'h420a;divider<=0;gap_count<=0;end
    end else if(divider!=QUARTER_CYCLES-1)divider<=divider+1;
    else begin
      divider<=0;
      case(state)
        GAP:if(gap_count==3)begin state<=START;gap_count<=0;end
            else gap_count<=gap_count+1'b1;
        START:begin sda_low<=1;scl_low<=0;bit_index<=0;second_byte<=0;state<=TX_LOW;end
        TX_LOW:begin scl_low<=1;sda_low<=(bit_index==8)?0:~tx_word[15];state<=TX_RISE;end
        TX_RISE:begin scl_low<=0;state<=TX_SAMPLE;end
        TX_SAMPLE:begin if(bit_index==8 && siod!=0)error<=1;state<=TX_FALL;end
        TX_FALL:begin
          scl_low<=1;
          if(bit_index==8)begin
            bit_index<=0;
            if(read_pass)begin rx_byte<=0;state<=RX_LOW;end
            else if(second_byte)state<=STOP_LOW;
            else begin second_byte<=1;state<=TX_LOW;end
          end else begin bit_index<=bit_index+1'b1;tx_word<=tx_word<<1;state<=TX_LOW;end
        end
        RX_LOW:begin scl_low<=1;sda_low<=0;state<=RX_RISE;end
        RX_RISE:begin scl_low<=0;state<=RX_SAMPLE;end
        RX_SAMPLE:begin if(bit_index<8)rx_byte<={rx_byte[6:0],siod};state<=RX_FALL;end
        RX_FALL:begin
          scl_low<=1;
          if(bit_index==8)state<=STOP_LOW;
          else begin bit_index<=bit_index+1'b1;state<=RX_LOW;end
        end
        STOP_LOW:begin scl_low<=1;sda_low<=1;state<=STOP_RISE;end
        STOP_RISE:begin scl_low<=0;state<=STOP_RELEASE;end
        STOP_RELEASE:begin sda_low<=0;state<=NEXT;end
        NEXT:begin
          if(!read_pass)begin read_pass<=1;tx_word<=16'h4300;state<=GAP;end
          else begin
            values[index*8+:8]<=rx_byte;
            if(index==3)begin done<=1;state<=FINISHED;end
            else begin index<=index+1'b1;read_pass<=0;tx_word<={8'h42,address(index+2'd1)};state<=GAP;end
          end
        end
        FINISHED:begin scl_low<=0;sda_low<=0;end
        default:state<=IDLE;
      endcase
    end
  end
endmodule
