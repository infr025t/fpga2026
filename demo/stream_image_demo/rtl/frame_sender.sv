`timescale 1ns/1ps
// Frozen framebuffer -> FPG1 packet. All inputs except RAM data latch at start.
// RAM must implement a synchronous one-cycle read; it remains frozen while busy.
module frame_sender #(
  parameter integer W=318,H=238,CLKS_PER_BIT=100,TARGET_PROTOCOL=0,OUTPUT_PROTOCOL=0
)(
  input wire clk,rst,start,edge_mode, input wire [10:0] threshold,
  input wire [31:0] frame_id,bright_count,sum_x,sum_y,
  output reg [16:0] ram_addr, input wire [7:0] ram_data,
  output wire busy, output reg done, output wire uart_txd,
  input wire target_enable,target_valid,target_dark,config_valid,
  input wire [7:0] target_threshold,
  input wire [15:0] roi_x_min,roi_y_min,roi_x_max,roi_y_max,
  input wire [15:0] bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max,
  input wire [31:0] target_area,target_sum_x,target_sum_y,min_area,max_area,
  input wire pack_edges,features_only
);
  localparam integer PIXELS=W*H;
  localparam [3:0] IDLE=0,HEADER=1,RAM_WAIT=2,RAM_CAPTURE=3,
    PIXEL=4,CRC_LO=5,CRC_HI=6,DRAIN=7;
  reg [3:0] state;
  reg [575:0] header;
  reg [6:0] header_index,header_length;
  reg [16:0] pixel_index;
  reg [7:0] pixel_byte;
  reg packed_output,features_output;
  reg [2:0] pack_index;
  reg [15:0] crc;
  // The default constant disables every new input, including unconnected ports
  // in legacy instantiations. Packet length is selected only when start latches.
  wire use_target=(TARGET_PROTOCOL!=0)?target_enable:1'b0;
  wire use_features=(OUTPUT_PROTOCOL!=0)?(use_target && features_only):1'b0;
  wire use_packed=(OUTPUT_PROTOCOL!=0)?(pack_edges && edge_mode && !use_features):1'b0;
  wire use_v3=use_features || use_packed;
  wire ready;
  wire valid=(state==HEADER || state==PIXEL || state==CRC_LO || state==CRC_HI);
  wire [7:0] data=(state==HEADER)?header[header_index*8 +: 8]:
    (state==PIXEL)?pixel_byte:(state==CRC_LO)?crc[7:0]:crc[15:8];
  assign busy=(state!=IDLE);
  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) tx(.clk(clk),.rst(rst),.valid(valid),.data(data),.ready(ready),.tx(uart_txd));
  function [15:0] crc_byte(input [15:0] old_crc,input [7:0] b);
    reg [15:0] c; integer i;
    begin c=old_crc^{b,8'b0};
      for(i=0;i<8;i=i+1) c=c[15]?(c<<1)^16'h1021:c<<1;
      crc_byte=c;
    end
  endfunction
  always @(posedge clk) begin
    if(rst) begin state<=IDLE; done<=0; ram_addr<=0; header<=0; header_index<=0; header_length<=32;
      pixel_index<=0; pixel_byte<=0; packed_output<=0; features_output<=0;
      pack_index<=0; crc<=16'hffff; end
    else begin
      done<=0;
      case(state)
        IDLE: if(start) begin
          header[31:0]<=32'h31475046;
          header[39:32]<=use_v3?8'd3:(use_target?8'd2:8'd1); header[47:40]<={7'b0,edge_mode};
          header[63:48]<=W; header[79:64]<=H;
          header[95:80]<={5'b0,threshold}; header[127:96]<=frame_id;
          header[159:128]<=use_features?0:(use_packed?((PIXELS+7)/8):PIXELS);
          header[191:160]<=bright_count;
          header[223:192]<=sum_x; header[255:224]<=sum_y;
          header[263:256]<={5'b0,config_valid,target_dark,target_valid};
          header[271:264]<=target_threshold;
          header[287:272]<=roi_x_min; header[303:288]<=roi_y_min;
          header[319:304]<=roi_x_max; header[335:320]<=roi_y_max;
          header[351:336]<=bbox_x_min; header[367:352]<=bbox_y_min;
          header[383:368]<=bbox_x_max; header[399:384]<=bbox_y_max;
          header[431:400]<=target_area; header[463:432]<=target_sum_x;
          header[495:464]<=target_sum_y; header[527:496]<=min_area;
          header[559:528]<=max_area;
          // A packed image can omit target detection. Its extension must be
          // deterministic even when target inputs are unconnected or changing.
          if(use_v3 && !use_target) header[559:256]<=0;
          header[567:560]<=use_features?8'd6:(use_packed?(use_target?8'd5:8'd1):8'd0);
          header[575:568]<=0;
          header_length<=(use_v3 || use_target)?7'd72:7'd32;
          packed_output<=use_packed; features_output<=use_features;
          header_index<=0; pixel_index<=0; ram_addr<=0; pixel_byte<=0; pack_index<=0;
          crc<=16'hffff; state<=HEADER;
        end
        HEADER: if(ready) begin
          if(header_index>=4) crc<=crc_byte(crc,data);
          if(header_index==header_length-1'b1) state<=features_output?CRC_LO:RAM_WAIT;
          else header_index<=header_index+1'b1;
        end
        // Address is presented before RAM_WAIT. Capture one full cycle later.
        RAM_WAIT: state<=RAM_CAPTURE;
        RAM_CAPTURE: begin
          if(packed_output) begin
            pixel_byte[pack_index]<=ram_data[7];
            if(pack_index==7 || pixel_index==PIXELS-1) state<=PIXEL;
            else begin
              pack_index<=pack_index+1'b1; pixel_index<=pixel_index+1'b1;
              ram_addr<=ram_addr+1'b1; state<=RAM_WAIT;
            end
          end else begin pixel_byte<=ram_data; state<=PIXEL; end
        end
        PIXEL: if(ready) begin
          crc<=crc_byte(crc,pixel_byte);
          if(pixel_index==PIXELS-1) state<=CRC_LO;
          else begin
            pixel_index<=pixel_index+1'b1; ram_addr<=ram_addr+1'b1;
            pack_index<=0; pixel_byte<=0; state<=RAM_WAIT;
          end
        end
        CRC_LO: if(ready) state<=CRC_HI;
        CRC_HI: if(ready) state<=DRAIN;
        DRAIN: if(ready) begin state<=IDLE; done<=1; end
        default: state<=IDLE;
      endcase
    end
  end
endmodule
