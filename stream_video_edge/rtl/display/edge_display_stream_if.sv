`timescale 1ns/1ps
// Coordinate/color interface only. No hidden image storage or core backpressure.
// FIFO/whole-frame admission to the physical writer must be implemented and
// validated when the final LCD board pin mapping and rate are confirmed.
module edge_display_stream_if(input wire valid,input wire[7:0]gray,
 input wire[9:0]x,input wire[8:0]y,
 output wire pixel_valid,output wire[15:0]rgb565,
 output wire[9:0]panel_x,output wire[8:0]panel_y);
 assign pixel_valid=valid;
 assign rgb565={gray[7:3],gray[7:2],gray[7:3]};
 // 640x480 logical canvas centered on an800x480 landscape panel.
 assign panel_x=x+10'd80;assign panel_y=y;
endmodule
