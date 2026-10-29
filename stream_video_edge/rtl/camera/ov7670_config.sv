`timescale 1ns/1ps
// Original SCCB write sequencer. Open-drain SIOC/SIOD need external pullups.
// 100 MHz / (4*250) = 100 kHz. No clock-stretch support (OV7670 SCCB).
// SCCB's ninth bit is formally don't-care; this module checks the ACK that
// common OV7670 modules provide. Set CHECK_ACK=0 only after scope diagnosis.
module ov7670_config #(
  parameter integer QUARTER_CYCLES=250,POWER_WAIT=10000000,REG_WAIT=100000,
  parameter integer CHECK_ACK=1,DIRECT_IO=1,FREEZE_AEC=0,FREEZE_AGC=0,AEC_SETTLE=200000000
)(input wire clk,rst,input wire slow_clock,scene,inout wire sioc,siod,output reg done,error,
  output wire scl_drive_low,sda_drive_low);
  reg scl_low,sda_low;
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
  localparam REG_COUNT=FREEZE_AEC?40:39;
  // Native VGA: COM3/COM14 disable DCW; UYVY (Y second), full-range Y.
  // Keep PCLK running in horizontal blanking for AL422B refresh.
  function automatic [15:0] setting(input [5:0]n);
    case(n)
      0:setting=16'h1280; // software reset; wait 100 ms afterward
      1:setting=slow_clock?16'h1103:16'h1101; // diagnostic /4 versus original /2
      2:setting=16'h6b0a; // PLL bypass
      3:setting=16'h1200; // YUV, VGA window before DCW
      4:setting=16'h0c00; // VGA: disable DCW/downsampling
      5:setting=16'h3e00; // VGA: no DCW or scaling PCLK divide
      6:setting=16'h703a;
      7:setting=16'h7135;
      8:setting=16'h7211; // reference DCW value; inactive with COM3/COM14=00
      9:setting=16'h73f0; // VGA scaling PCLK divider, no /2
     10:setting=16'ha202;
     11:setting=16'h1713; // window high and low bits must be a matched set
     12:setting=16'h1801;
     13:setting=16'h3236; // matched VGA window 158/14; preserve HREF edge-offset bits
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
     38:setting=scene?16'h4200:16'h4208; // same capture, scene versus sensor bars
     39:setting=FREEZE_AGC?16'h13e2:16'h13e6; // freeze AEC and optionally AGC after settling
     default:setting=16'hffff;
    endcase
  endfunction
  always @(posedge clk) begin
    if(rst)begin
      scl_low<=0;sda_low<=0;done<=0;error<=0;divider<=0;
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
          if(bit_pos==8 && CHECK_ACK && siod!=1'b0)error<=1;
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
        NEXT_REG:if(error)state<=FAILED;
          else if(index==REG_COUNT-1)begin done<=1;state<=FINISHED;end
          else begin index<=index+1'b1;wait_count<=(index==0)?POWER_WAIT:((FREEZE_AEC&&index==38)?AEC_SETTLE:REG_WAIT);state<=WAITING;end
        FINISHED:done<=1;
        FAILED:begin scl_low<=0;sda_low<=0;end
        default:state<=WAITING;
      endcase
    end
  end
endmodule
