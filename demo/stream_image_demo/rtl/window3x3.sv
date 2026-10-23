`timescale 1ns/1ps
// One accepted sample per clock, with arbitrary bubbles between samples.
// frame_start may accompany the first sample. RAM contents are never reset.
module window3x3 #(parameter integer W=320,H=240,DATA_WIDTH=8)(
  input wire clk,rst,frame_start,in_valid,
  input wire[DATA_WIDTH-1:0]in_data,
  output reg out_valid,output reg[9*DATA_WIDTH-1:0]window_data,
  output reg[15:0]center_x,center_y
);
  localparam integer XW=(W<2)?1:$clog2(W),YW=(H<2)?1:$clog2(H);
  (* ram_style="block" *) reg[DATA_WIDTH-1:0]row0[0:W-1],row1[0:W-1],row2[0:W-1];
  reg[DATA_WIDTH-1:0]q0,q1,q2,pixel_pending;
  reg[DATA_WIDTH-1:0]t0,t1,m0,m1,b0,b1;
  reg[XW-1:0]x,px;reg[YW-1:0]y,py;
  reg[1:0]bank,pbank;reg active,pending;
  wire accept=in_valid && (active || frame_start) && !rst;
  wire[XW-1:0]write_x=frame_start?0:x;
  wire[1:0]write_bank=frame_start?0:bank;
  wire[DATA_WIDTH-1:0]top_value=(pbank==0)?q1:(pbank==1)?q2:q0;
  wire[DATA_WIDTH-1:0]mid_value=(pbank==0)?q2:(pbank==1)?q0:q1;
  always @(posedge clk)if(accept)begin
    q0<=row0[write_x];q1<=row1[write_x];q2<=row2[write_x];
    case(write_bank)
      0:row0[write_x]<=in_data;1:row1[write_x]<=in_data;2:row2[write_x]<=in_data;
    endcase
  end
  always @(posedge clk)begin
    if(rst)begin
      x<=0;y<=0;px<=0;py<=0;bank<=0;pbank<=0;active<=0;pending<=0;
      out_valid<=0;window_data<=0;center_x<=0;center_y<=0;pixel_pending<=0;
      t0<=0;t1<=0;m0<=0;m1<=0;b0<=0;b1<=0;
    end else if(frame_start)begin
      x<=in_valid?1:0;y<=0;bank<=0;active<=1;pending<=in_valid;
      px<=0;py<=0;pbank<=0;pixel_pending<=in_data;out_valid<=0;
      t0<=0;t1<=0;m0<=0;m1<=0;b0<=0;b1<=0;
    end else begin
      pending<=accept;out_valid<=0;
      if(accept)begin
        px<=x;py<=y;pbank<=bank;pixel_pending<=in_data;
        if(x==W-1)begin
          x<=0;bank<=(bank==2)?0:bank+1'b1;
          if(y==H-1)active<=0;else y<=y+1'b1;
        end else x<=x+1'b1;
      end
      if(pending)begin
        t0<=t1;t1<=top_value;m0<=m1;m1<=mid_value;b0<=b1;b1<=pixel_pending;
        if(px>=2 && py>=2)begin
          // Low byte/word is the top-left member, row-major thereafter.
          window_data<={pixel_pending,b1,b0,mid_value,m1,m0,top_value,t1,t0};
          center_x<=px-1'b1;center_y<=py-1'b1;out_valid<=1;
        end
      end
    end
  end
endmodule
