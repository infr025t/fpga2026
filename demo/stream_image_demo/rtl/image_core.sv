`timescale 1ns/1ps
module image_core #(parameter W=320,H=240)(
input clk,rst,frame_start,edge_mode,input [10:0] threshold,
input in_valid,input [7:0] in_pixel,output reg out_valid,
output reg [7:0] out_pixel,output reg [16:0] out_addr,
output reg done,output reg [31:0] bright_count,sum_x,sum_y);
  // Contract: W,H >= 3, W*H <= 131072; input pixels >= 4 clocks apart.
  // Three rotating banks keep writes separate from the two previous rows.
  // Only RAM output registers, never the RAM contents, enter the pipeline.
  localparam XW=$clog2(W), YW=$clog2(H);
  (* ram_style="block" *) reg [7:0] row0[0:W-1];
  (* ram_style="block" *) reg [7:0] row1[0:W-1];
  (* ram_style="block" *) reg [7:0] row2[0:W-1];
  reg [7:0] q0,q1,q2;
  reg [XW-1:0] x,px,cx;
  reg [YW-1:0] y,py,cy;
  reg [1:0] bank,pbank;
  reg active,mode_latched,pending,window_valid,last_window,last_output;
  reg [10:0] threshold_latched;
  reg [7:0] pixel_pending;
  reg [7:0] tl,tc,tr,ml,mc,mr,bl,bc,br;
  reg [16:0] next_addr;
  // Four arithmetic stages: weighted sides, signed difference, absolute value,
  // then magnitude/threshold. Metadata follows the same valid pipeline.
  reg [9:0] right_sum,left_sum,bottom_sum,top_sum;
  reg signed [10:0] gx_reg,gy_reg;
  reg [10:0] ax_reg,ay_reg;
  reg sides_valid,gradient_valid,absolute_valid;
  reg sides_last,gradient_last,absolute_last;
  reg [7:0] sides_center,gradient_center,absolute_center;
  reg [XW-1:0] sides_x,gradient_x,absolute_x;
  reg [YW-1:0] sides_y,gradient_y,absolute_y;
  wire accept=in_valid && active && !rst && !frame_start;
  wire [7:0] top_value=(pbank==0)?q1:((pbank==1)?q2:q0);
  wire [7:0] mid_value=(pbank==0)?q2:((pbank==1)?q0:q1);
  wire [11:0] magnitude={1'b0,ax_reg}+{1'b0,ay_reg}; // conservative max 2040

  // Synchronous simple dual-port RAM templates; no reset on memory/read ports.
  always @(posedge clk) if(accept) begin
    q0<=row0[x]; q1<=row1[x]; q2<=row2[x];
    case(bank)
      0: row0[x]<=in_pixel;
      1: row1[x]<=in_pixel;
      2: row2[x]<=in_pixel;
    endcase
  end
  always @(posedge clk) begin
    if(rst || frame_start) begin
      x<=0;y<=0;bank<=0;active<=!rst;
      pending<=0;window_valid<=0;last_window<=0;last_output<=0;
      sides_valid<=0;gradient_valid<=0;absolute_valid<=0;
      sides_last<=0;gradient_last<=0;absolute_last<=0;
      sides_center<=0;gradient_center<=0;absolute_center<=0;
      sides_x<=0;gradient_x<=0;absolute_x<=0;
      sides_y<=0;gradient_y<=0;absolute_y<=0;
      right_sum<=0;left_sum<=0;bottom_sum<=0;top_sum<=0;
      gx_reg<=0;gy_reg<=0;ax_reg<=0;ay_reg<=0;
      out_valid<=0;out_pixel<=0;out_addr<=0;next_addr<=0;done<=0;
      bright_count<=0;sum_x<=0;sum_y<=0;
      mode_latched<=edge_mode;threshold_latched<=threshold;
      tl<=0;tc<=0;tr<=0;ml<=0;mc<=0;mr<=0;bl<=0;bc<=0;br<=0;
      px<=0;py<=0;cx<=0;cy<=0;pbank<=0;pixel_pending<=0;
    end else begin
      pending<=accept;window_valid<=0;out_valid<=0;
      sides_valid<=window_valid;gradient_valid<=sides_valid;absolute_valid<=gradient_valid;
      done<=last_output;last_output<=0;
      if(accept) begin
        px<=x;py<=y;pbank<=bank;pixel_pending<=in_pixel;
        if(x==W-1) begin
          x<=0;
          bank<=(bank==2)?0:bank+1'b1;
          if(y==H-1) active<=0; else y<=y+1'b1;
        end else x<=x+1'b1;
      end
      if(pending) begin
        tl<=tc;tc<=tr;tr<=top_value;
        ml<=mc;mc<=mr;mr<=mid_value;
        bl<=bc;bc<=br;br<=pixel_pending;
        // The first two columns replace stale shift-register values each row.
        window_valid<=(px>=2 && py>=2);
        cx<=px-1'b1;cy<=py-1'b1;
        last_window<=(px==W-1 && py==H-1);
      end
      if(window_valid) begin
        right_sum<={2'b0,tr}+{1'b0,mr,1'b0}+{2'b0,br};
        left_sum<={2'b0,tl}+{1'b0,ml,1'b0}+{2'b0,bl};
        bottom_sum<={2'b0,bl}+{1'b0,bc,1'b0}+{2'b0,br};
        top_sum<={2'b0,tl}+{1'b0,tc,1'b0}+{2'b0,tr};
        sides_center<=mc;sides_x<=cx;sides_y<=cy;sides_last<=last_window;
      end
      if(sides_valid) begin
        gx_reg<=$signed({1'b0,right_sum})-$signed({1'b0,left_sum});
        gy_reg<=$signed({1'b0,bottom_sum})-$signed({1'b0,top_sum});
        gradient_center<=sides_center;gradient_x<=sides_x;gradient_y<=sides_y;gradient_last<=sides_last;
      end
      if(gradient_valid) begin
        ax_reg<=gx_reg[10]?-gx_reg:gx_reg;
        ay_reg<=gy_reg[10]?-gy_reg:gy_reg;
        absolute_center<=gradient_center;absolute_x<=gradient_x;absolute_y<=gradient_y;absolute_last<=gradient_last;
      end
      if(absolute_valid) begin
        out_valid<=1;out_addr<=next_addr;next_addr<=next_addr+1'b1;
        out_pixel<=mode_latched?((magnitude>={1'b0,threshold_latched})?8'd255:8'd0):absolute_center;
        if(absolute_center>=128) begin
          bright_count<=bright_count+1'b1;sum_x<=sum_x+absolute_x;sum_y<=sum_y+absolute_y;
        end
        last_output<=absolute_last;
      end
    end
  end
endmodule
