`timescale 1ns/1ps
module source_pattern #(parameter integer W=640,H=480,PATTERN_ID=0,L_CORE=core_latency_pkg::L_CORE)(
  input wire clk,rst,enable,output wire token_valid,output wire [63:0] token,
  output wire end_valid,output video_runtime_pkg::source_end_t end_status
);
  reg active;reg [9:0] x;reg [8:0] y;reg [31:0] frame_id;
  reg [$clog2(L_CORE+1)-1:0] gap;
  reg [7:0] pixel;
  wire last=x==W-1 && y==H-1;
  assign token_valid=!rst && gap==0 && (active || enable);
  always @*case(PATTERN_ID)
    0:pixel=x+y+frame_id;
    1:pixel=(((x/16)+(y/16))%2==0)?32:224;
    2:pixel=(2*x<W)?32:224;
    default:pixel=128;
  endcase
  assign token=video_runtime_pkg::pack_pixel(pixel,x,y,token_valid && x==0 && y==0,
    token_valid && x==W-1,token_valid && last,frame_id);
  assign end_valid=token_valid && last;
  assign end_status={frame_id,1'b1,4'd0};
  initial if(W<16 || W>640 || H<16 || H>480 || PATTERN_ID<0 || PATTERN_ID>3 || L_CORE<1)
    $fatal(1,"illegal pattern source parameters");
  always @(posedge clk)begin
    if(rst)begin active<=0;x<=0;y<=0;frame_id<=0;gap<=0;end
    else begin
      if(gap!=0)gap<=gap-1'b1;
      if(token_valid)begin
        active<=1;
        if(x==W-1)begin
          x<=0;
          if(last)begin y<=0;active<=0;frame_id<=frame_id+1'b1;gap<=L_CORE;end
          else y<=y+1'b1;
        end else x<=x+1'b1;
      end
    end
  end
endmodule
