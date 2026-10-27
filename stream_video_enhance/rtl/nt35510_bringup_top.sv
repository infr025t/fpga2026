`timescale 1ns/1ps
// Pin-independent Basys3 bring-up wrapper. A board-specific XDC must be written
// only after the actual adapter, interface straps and physical wires are checked.
module nt35510_bringup_top(
  input wire clk100,btnC,input wire [15:0] sw,
  output wire [7:0] lcd_data,output wire lcd_cs_n,lcd_rs,lcd_wr_n,lcd_rd_n,lcd_reset_n,lcd_bl,
  output wire [15:0] led
);
  (* ASYNC_REG="TRUE" *) reg [1:0] button_sync=0;
  (* ASYNC_REG="TRUE" *) reg [15:0] sw_meta=0,sw_sync=0;
  reg [15:0] reset_hold=16'hffff;
  always @(posedge clk100)begin
    button_sync<={button_sync[0],btnC};
    reset_hold<=button_sync[1]?16'hffff:{reset_hold[14:0],1'b0};
    sw_meta<=sw;sw_sync<=sw_meta;
  end
  wire rst=|reset_hold;
  wire initialized,background_done,frame_done,busy,error;
  wire [31:0] frames;
  nt35510_test_display display(.clk(clk100),.rst(rst),.enable(!sw_sync[15]),.pattern_select(sw_sync[1:0]),
    .lcd_data(lcd_data),.lcd_cs_n(lcd_cs_n),.lcd_rs(lcd_rs),.lcd_wr_n(lcd_wr_n),
    .lcd_rd_n(lcd_rd_n),.lcd_reset_n(lcd_reset_n),.lcd_bl(lcd_bl),
    .initialized(initialized),.background_done(background_done),.frame_done(frame_done),
    .rendered_frames(frames),.busy(busy),.error(error));
  assign led={frames[7:0],error,sw_sync[15],lcd_bl,lcd_reset_n,busy,frame_done,background_done,initialized};
endmodule
