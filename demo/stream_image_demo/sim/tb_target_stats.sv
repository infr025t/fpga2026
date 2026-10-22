`timescale 1ns/1ps
module tb_target_stats;
  parameter integer W=9,H=8,LARGE_ONLY=0;
  localparam integer N=W*H,INTERIOR=(W-2)*(H-2);
  reg clk=0;always #5 clk=~clk;
  reg rst=1,frame_start=0,in_valid=0,target_dark=1;
  reg [7:0] in_pixel=0,target_threshold=96;
  reg [15:0] roi_x_min=1,roi_y_min=1,roi_x_max=W-2,roi_y_max=H-2;
  reg [31:0] min_area=1,max_area=INTERIOR;
  wire done,config_valid,target_valid;
  wire [31:0] target_area,target_sum_x,target_sum_y;
  wire [15:0] bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max;
  target_stats #(.W(W),.H(H)) dut(
    .clk(clk),.rst(rst),.frame_start(frame_start),.in_valid(in_valid),.in_pixel(in_pixel),
    .target_dark(target_dark),.target_threshold(target_threshold),
    .roi_x_min(roi_x_min),.roi_y_min(roi_y_min),.roi_x_max(roi_x_max),.roi_y_max(roi_y_max),
    .min_area(min_area),.max_area(max_area),.done(done),.config_valid(config_valid),
    .target_valid(target_valid),.target_area(target_area),.target_sum_x(target_sum_x),
    .target_sum_y(target_sum_y),.bbox_x_min(bbox_x_min),.bbox_y_min(bbox_y_min),
    .bbox_x_max(bbox_x_max),.bbox_y_max(bbox_y_max));
  reg [7:0] src[0:N-1];
  integer expected_area,expected_sx,expected_sy,expected_x0,expected_y0,expected_x1,expected_y1;
  reg expected_config,expected_valid;
  integer k,x,y,frames=0;

  task defaults;
    begin
      target_dark=1;target_threshold=96;
      roi_x_min=1;roi_y_min=1;roi_x_max=W-2;roi_y_max=H-2;
      min_area=1;max_area=INTERIOR;
    end
  endtask
  task fill(input [7:0] value);
    integer i;
    begin for(i=0;i<N;i=i+1)src[i]=value;end
  endtask
  task rectangle(input integer x0,y0,x1,y1,input [7:0] value);
    integer xx,yy;
    begin for(yy=y0;yy<=y1;yy=yy+1)for(xx=x0;xx<=x1;xx=xx+1)src[yy*W+xx]=value;end
  endtask
  task reference_model;
    integer xx,yy;
    begin
      expected_config=(roi_x_min>=1 && roi_x_min<=roi_x_max && roi_x_max<=W-2 &&
        roi_y_min>=1 && roi_y_min<=roi_y_max && roi_y_max<=H-2 &&
        min_area>=1 && min_area<=max_area && max_area<=INTERIOR);
      expected_area=0;expected_sx=0;expected_sy=0;
      expected_x0=0;expected_y0=0;expected_x1=0;expected_y1=0;
      for(yy=0;yy<H;yy=yy+1)for(xx=0;xx<W;xx=xx+1)
        if(expected_config && xx>=roi_x_min && xx<=roi_x_max && yy>=roi_y_min && yy<=roi_y_max &&
            (target_dark?(src[yy*W+xx]<=target_threshold):(src[yy*W+xx]>=target_threshold)))begin
          if(expected_area==0)begin expected_x0=xx;expected_x1=xx;expected_y0=yy;expected_y1=yy;end
          else begin
            if(xx<expected_x0)expected_x0=xx;if(xx>expected_x1)expected_x1=xx;
            if(yy<expected_y0)expected_y0=yy;if(yy>expected_y1)expected_y1=yy;
          end
          expected_area=expected_area+1;expected_sx=expected_sx+xx;expected_sy=expected_sy+yy;
        end
      expected_valid=expected_config && expected_area>0 && expected_area>=min_area && expected_area<=max_area;
    end
  endtask
  task check_results(input string label);
    begin
      if(config_valid!==expected_config || target_valid!==expected_valid ||
          target_area!==expected_area || target_sum_x!==expected_sx || target_sum_y!==expected_sy ||
          bbox_x_min!==expected_x0 || bbox_y_min!==expected_y0 || bbox_x_max!==expected_x1 || bbox_y_max!==expected_y1)
        $fatal(1,"%s result mismatch config=%b/%b valid=%b/%b area=%0d/%0d sum=%0d,%0d/%0d,%0d bbox=%0d,%0d,%0d,%0d/%0d,%0d,%0d,%0d",
          label,config_valid,expected_config,target_valid,expected_valid,target_area,expected_area,
          target_sum_x,target_sum_y,expected_sx,expected_sy,bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max,
          expected_x0,expected_y0,expected_x1,expected_y1);
    end
  endtask
  task begin_frame;
    begin
      @(negedge clk);frame_start=1;in_valid=0;
      @(negedge clk);frame_start=0;
      if(done!==0 || target_area!==0 || target_sum_x!==0 || target_sum_y!==0 ||
          bbox_x_min!==0 || bbox_y_min!==0 || bbox_x_max!==0 || bbox_y_max!==0)
        $fatal(1,"frame_start did not clear results/done");
    end
  endtask
  task finish_frame(input string label,input integer gaps,mutate);
    integer i;
    begin
      for(i=0;i<N;i=i+1)begin
        if(mutate && i==N/2)begin
          target_dark=!target_dark;target_threshold=255;roi_x_min=0;roi_y_max=0;min_area=0;max_area=0;
        end
        in_valid=1;in_pixel=src[i];@(negedge clk);
        if(done!==0)$fatal(1,"%s done before final input retired",label);
        if(gaps && i!=N-1)begin
          in_valid=0;repeat(i%3+1)begin
            @(negedge clk);if(done!==0)$fatal(1,"%s done in input gap",label);
          end
        end
      end
      in_valid=0;
      // Last raw pixel has retired; done must be delayed one cycle.
      check_results(label);
      @(negedge clk);if(done!==1)$fatal(1,"%s missing delayed done",label);
      check_results(label);
      @(negedge clk);if(done!==0)$fatal(1,"%s done wider than one cycle",label);
      check_results(label);
      // Extra samples after W*H cannot change the completed result.
      in_valid=1;in_pixel=0;
      repeat(5)begin @(negedge clk);if(done!==0)$fatal(1,"extra-input done");check_results(label);end
      in_valid=0;
      frames=frames+1;
      $display("PASS target_stats %s area=%0d valid=%b",label,target_area,target_valid);
    end
  endtask
  task run_frame(input string label,input integer gaps,mutate);
    begin reference_model();begin_frame();finish_frame(label,gaps,mutate);end
  endtask
  task partial_frame;
    integer i;
    begin
      begin_frame();
      for(i=0;i<N/2;i=i+1)begin
        in_valid=1;in_pixel=0;@(negedge clk);
        if(done!==0)$fatal(1,"partial frame completed");
      end
      in_valid=0;
      if(target_area==0)$fatal(1,"partial-frame test did not accumulate any target");
    end
  endtask

  initial begin
    repeat(3)@(negedge clk);rst=0;
    if(LARGE_ONLY)begin
      defaults();fill(240);src[(H-2)*W+W-2]=96;
      run_frame("large_last_roi_pixel",0,0);
      defaults();fill(0);max_area=INTERIOR/2;
      run_frame("large_all_roi_above_max",0,0);
      if(target_area!==75684 || target_sum_x!==12071598 || target_sum_y!==9044238 || target_valid!==0)
        $fatal(1,"QVGA full-ROI area/sum/filter regression");
      $display("PASS_TARGET_STATS_QVGA frames=%0d W=%0d H=%0d area=%0d sums=%0d,%0d",frames,W,H,
        target_area,target_sum_x,target_sum_y);
      $finish;
    end
    in_valid=1;in_pixel=0;repeat(N+2)begin
      @(negedge clk);if(done!==0 || target_area!==0 || config_valid!==0)$fatal(1,"input accepted before frame_start");
    end
    in_valid=0;
    defaults();fill(240);run_frame("no_target",1,0);
    defaults();fill(240);rectangle(2,2,5,4,32);run_frame("dark_rectangle",0,0);
    defaults();target_dark=0;fill(10);rectangle(1,1,6,5,220);run_frame("bright_rectangle",1,0);
    defaults();fill(0);roi_x_min=3;roi_y_min=2;roi_x_max=5;roi_y_max=4;
    rectangle(3,2,5,4,240);src[3*W+4]=96;run_frame("roi_excludes_distractors",0,0);
    defaults();fill(240);src[1*W+1]=96;src[1*W+W-2]=96;
    src[(H-2)*W+1]=96;src[(H-2)*W+W-2]=96;
    rectangle(0,0,W-1,0,0);rectangle(0,H-1,W-1,H-1,0);
    src[3*W]=0;src[3*W+W-1]=0;run_frame("inclusive_roi_corners_exclude_border",0,0);
    defaults();fill(240);src[(H-2)*W+W-2]=96;run_frame("last_roi_pixel",0,0);
    defaults();target_dark=0;fill(0);src[(H-2)*W+W-2]=96;run_frame("bright_threshold_equality",0,0);
    defaults();fill(240);rectangle(2,2,3,3,0);min_area=4;max_area=4;run_frame("exact_area_limits",0,0);
    defaults();fill(240);rectangle(2,2,3,3,0);min_area=5;run_frame("below_min_keeps_raw_statistics",0,0);
    defaults();fill(240);rectangle(2,2,3,3,0);max_area=3;run_frame("above_max_keeps_raw_statistics",0,0);
    defaults();target_threshold=0;fill(1);src[2*W+2]=0;run_frame("threshold_zero",0,0);
    defaults();target_dark=0;target_threshold=255;fill(254);src[2*W+2]=255;run_frame("threshold_255",0,0);
    defaults();fill(0);roi_x_min=0;run_frame("invalid_roi_zero",0,0);
    defaults();roi_y_max=H-1;run_frame("invalid_roi_border",0,0);
    defaults();roi_x_min=5;roi_x_max=4;run_frame("invalid_roi_reversed_x",0,0);
    defaults();roi_y_min=5;roi_y_max=4;run_frame("invalid_roi_reversed_y",0,0);
    defaults();min_area=0;run_frame("invalid_area_zero",0,0);
    defaults();min_area=5;max_area=4;run_frame("invalid_area_reversed",0,0);
    defaults();max_area=INTERIOR+1;run_frame("invalid_area_too_large",0,0);
    defaults();fill(240);rectangle(2,2,5,4,20);run_frame("latched_configuration",1,1);
    defaults();partial_frame();
    defaults();fill(240);src[W+1]=0;run_frame("frame_start_aborts_partial",0,0);
    defaults();partial_frame();
    rst=1;in_valid=1;@(negedge clk);
    if(done!==0 || config_valid!==0 || target_valid!==0 || target_area!==0 || target_sum_x!==0 || target_sum_y!==0 ||
        bbox_x_min!==0 || bbox_y_min!==0 || bbox_x_max!==0 || bbox_y_max!==0)$fatal(1,"reset did not clear statistics");
    rst=0;
    repeat(N+2)begin @(negedge clk);if(done!==0 || target_area!==0)$fatal(1,"reset did not abort frame");end
    in_valid=0;
    defaults();fill(240);src[2*W+3]=0;run_frame("frame_after_reset",0,0);
    // Suppress the completion pending from an old frame with a new start.
    defaults();fill(240);begin_frame();
    for(k=0;k<N;k=k+1)begin in_valid=1;in_pixel=0;@(negedge clk);if(done!==0)$fatal(1,"early completion");end
    frame_start=1;in_valid=1;in_pixel=0;
    @(negedge clk);frame_start=0;in_valid=0;
    if(done!==0 || target_area!==0)$fatal(1,"new frame_start did not supersede pending completion");
    reference_model();finish_frame("new_start_cancels_pending_done",0,0);
    // Reset also takes priority over frame_start and pending completion.
    defaults();begin_frame();
    for(k=0;k<N;k=k+1)begin in_valid=1;in_pixel=0;@(negedge clk);end
    rst=1;frame_start=1;
    @(negedge clk);rst=0;frame_start=0;in_valid=0;
    if(done!==0 || config_valid!==0 || target_area!==0)$fatal(1,"reset priority or pending completion failure");
    repeat(3)begin @(negedge clk);if(done!==0)$fatal(1,"completion survived reset");end
    $display("PASS_TARGET_STATS frames=%0d ROI polarity/threshold/configuration/area/bbox/latching/abort/reset/done",frames);
    $finish;
  end
  initial begin #100000000;$fatal(1,"target_stats test timeout");end
endmodule
