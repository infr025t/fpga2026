`timescale 1ns/1ps
// Inclusive ROI threshold statistics in original sensor coordinates.
// Configuration and results belong to one frame; frame_start aborts any work.
module target_stats #(parameter integer W=320,H=240)(
  input wire clk,rst,frame_start,in_valid,
  input wire [7:0] in_pixel,
  input wire target_dark,
  input wire [7:0] target_threshold,
  input wire [15:0] roi_x_min,roi_y_min,roi_x_max,roi_y_max,
  input wire [31:0] min_area,max_area,
  output reg done,config_valid,
  output wire target_valid,
  output reg [31:0] target_area,target_sum_x,target_sum_y,
  output reg [15:0] bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max
);
  localparam integer XW=(W<2)?1:$clog2(W),YW=(H<2)?1:$clog2(H);
  localparam integer INTERIOR_PIXELS=(W-2)*(H-2);
  reg [XW-1:0] x;
  reg [YW-1:0] y;
  reg active,finish_pending,dark_latched;
  reg [7:0] threshold_latched;
  reg [15:0] x_min_latched,y_min_latched,x_max_latched,y_max_latched;
  reg [31:0] min_area_latched,max_area_latched;
  wire valid_configuration=(W>=3 && H>=3 &&
    roi_x_min>=1 && roi_x_min<=roi_x_max && roi_x_max<=W-2 &&
    roi_y_min>=1 && roi_y_min<=roi_y_max && roi_y_max<=H-2 &&
    min_area>=1 && min_area<=max_area && max_area<=INTERIOR_PIXELS);
  wire matching_pixel=config_valid &&
    x>=x_min_latched && x<=x_max_latched &&
    y>=y_min_latched && y<=y_max_latched &&
    (dark_latched?(in_pixel<=threshold_latched):(in_pixel>=threshold_latched));
  assign target_valid=config_valid && target_area!=0 &&
    target_area>=min_area_latched && target_area<=max_area_latched;

  always @(posedge clk) begin
    if(rst) begin
      x<=0;y<=0;active<=0;finish_pending<=0;done<=0;config_valid<=0;
      dark_latched<=0;threshold_latched<=0;
      x_min_latched<=0;y_min_latched<=0;x_max_latched<=0;y_max_latched<=0;
      min_area_latched<=0;max_area_latched<=0;
      target_area<=0;target_sum_x<=0;target_sum_y<=0;
      bbox_x_min<=0;bbox_y_min<=0;bbox_x_max<=0;bbox_y_max<=0;
    end else if(frame_start) begin
      x<=0;y<=0;active<=1;finish_pending<=0;done<=0;
      config_valid<=valid_configuration;
      dark_latched<=target_dark;threshold_latched<=target_threshold;
      x_min_latched<=roi_x_min;y_min_latched<=roi_y_min;
      x_max_latched<=roi_x_max;y_max_latched<=roi_y_max;
      min_area_latched<=min_area;max_area_latched<=max_area;
      target_area<=0;target_sum_x<=0;target_sum_y<=0;
      bbox_x_min<=0;bbox_y_min<=0;bbox_x_max<=0;bbox_y_max<=0;
    end else begin
      done<=finish_pending;
      finish_pending<=0;
      if(in_valid && active) begin
        if(matching_pixel) begin
          target_area<=target_area+1'b1;
          target_sum_x<=target_sum_x+x;
          target_sum_y<=target_sum_y+y;
          if(target_area==0) begin
            bbox_x_min<=x;bbox_x_max<=x;bbox_y_min<=y;bbox_y_max<=y;
          end else begin
            if(x<bbox_x_min)bbox_x_min<=x;
            if(x>bbox_x_max)bbox_x_max<=x;
            if(y<bbox_y_min)bbox_y_min<=y;
            if(y>bbox_y_max)bbox_y_max<=y;
          end
        end
        if(x==W-1) begin
          x<=0;
          if(y==H-1) begin active<=0;finish_pending<=1;end
          else y<=y+1'b1;
        end else x<=x+1'b1;
      end
    end
  end
endmodule
