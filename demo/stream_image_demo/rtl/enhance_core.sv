`timescale 1ns/1ps
// Two 3x3 scales -> aligned raw/fine/coarse -> Q4 detail reconstruction.
// W,H >= 5. Output is (W-4)x(H-4), sensor coordinates 2..W-3,2..H-3.
// Accepts one pixel/clock; frame_start may accompany pixel (0,0).
module enhance_core #(parameter integer W=320,H=240,EPSILON_FINE=64,EPSILON_COARSE=256)(
  input wire clk,rst,frame_start,in_valid,input wire[7:0]in_pixel,
  input wire[7:0]fine_gain_q4,coarse_gain_q4,detail_limit,
  output reg out_valid,output reg[7:0]out_raw,out_fine,out_coarse,out_enhanced,
  output reg[15:0]out_x,out_y,output wire out_sof,out_eol,out_eof
);
  wire valid_w1,valid_b1,valid_w2,valid_b2;
  wire[71:0]w1,w2;wire[143:0]w2_pair;
  wire[15:0]wx1,wy1,x1,y1,wx2,wy2,x2,y2;
  wire[7:0]raw1,base1,raw2,fine2,base2,unused_fine;
  reg[7:0]gain_fine,gain_coarse,limit_latched;
  window3x3 #(.W(W),.H(H)) first_window(clk,rst,frame_start,in_valid,in_pixel,
    valid_w1,w1,wx1,wy1);
  edge_preserve9 #(.EPSILON(EPSILON_FINE)) fine_filter(clk,rst||frame_start,
    valid_w1,w1,w1[32+:8],w1[32+:8],wx1,wy1,valid_b1,raw1,unused_fine,base1,x1,y1);
  wire second_start=valid_b1 && x1==1 && y1==1;
  window3x3 #(.W(W-2),.H(H-2),.DATA_WIDTH(16)) second_window(
    clk,rst||frame_start,second_start,valid_b1,{raw1,base1},valid_w2,w2_pair,wx2,wy2);
  genvar g;generate for(g=0;g<9;g=g+1)begin:unpack_base
    assign w2[g*8+:8]=w2_pair[g*16+:8];
  end endgenerate
  edge_preserve9 #(.EPSILON(EPSILON_COARSE)) coarse_filter(clk,rst||frame_start,
    valid_w2,w2,w2_pair[72+:8],w2_pair[64+:8],wx2+16'd1,wy2+16'd1,
    valid_b2,raw2,fine2,base2,x2,y2);
  wire signed[9:0]df=$signed({2'b0,raw2})-$signed({2'b0,fine2});
  wire signed[9:0]dc=$signed({2'b0,fine2})-$signed({2'b0,base2});
  wire signed[9:0]lim=$signed({2'b0,limit_latched});
  wire signed[9:0]clip_f=(df>lim)?lim:((df < -lim)?-lim:df);
  wire signed[9:0]clip_c=(dc>lim)?lim:((dc < -lim)?-lim:dc);
  reg signed[19:0]product_f,product_c;
  reg[7:0]raw3,fine3,base3;reg[15:0]x3,y3;reg v3;
  wire signed[23:0]detail_sum=$signed(product_f)+$signed(product_c);
  wire signed[23:0]reconstructed=$signed({1'b0,base3})+(detail_sum>>>4);
  assign out_sof=out_valid && out_x==2 && out_y==2;
  assign out_eol=out_valid && out_x==W-3;
  assign out_eof=out_eol && out_y==H-3;
  always @(posedge clk)begin
    if(rst || frame_start)begin
      gain_fine<=fine_gain_q4;gain_coarse<=coarse_gain_q4;limit_latched<=detail_limit;
      v3<=0;out_valid<=0;product_f<=0;product_c<=0;raw3<=0;fine3<=0;base3<=0;x3<=0;y3<=0;
      out_raw<=0;out_fine<=0;out_coarse<=0;out_enhanced<=0;out_x<=0;out_y<=0;
    end else begin
      v3<=valid_b2;out_valid<=v3;
      if(valid_b2)begin
        product_f<=clip_f*$signed({1'b0,gain_fine});
        product_c<=clip_c*$signed({1'b0,gain_coarse});
        raw3<=raw2;fine3<=fine2;base3<=base2;x3<=x2;y3<=y2;
      end
      if(v3)begin
        out_raw<=raw3;out_fine<=fine3;out_coarse<=base3;out_x<=x3;out_y<=y3;
        out_enhanced<=(reconstructed<0)?0:((reconstructed>255)?255:reconstructed[7:0]);
      end
    end
  end
endmodule
