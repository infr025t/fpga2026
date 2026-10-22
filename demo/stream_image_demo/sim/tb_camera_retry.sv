`timescale 1ns/1ps
// Retry boundaries: 0 keeps manual recovery, 1 retries after a completed STOP.
// Both camera buses have pullups but no slave, so every write receives NACK.
module tb_camera_retry;
  reg clk=0;always #5 clk=~clk;
  reg button=1;
  reg[15:0]sw=0;
  tri1 scl_off,sda_off,reset_off,scl_one,sda_one,reset_one;
  wire tx_off,tx_one;
  wire[15:0]led_off,led_one;
  integer retries=0,cycles=0,first_error=-1,last_error=-1;
  reg previous_reset=1,previous_error=0,saw_fault=0;
  stream_top #(.W(3),.H(3),.START_DELAY(0),.CAM_RESET_CYCLES(3),
    .CAM_SETTLE_CYCLES(4),.CAM_RETRY_CYCLES(0)) retry_off(
    .clk100(clk),.btnC(button),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_sioc(scl_off),.cam_siod(sda_off),.cam_rst_n(reset_off),.uart_txd(tx_off),.led(led_off));
  stream_top #(.W(3),.H(3),.START_DELAY(0),.CAM_RESET_CYCLES(3),
    .CAM_SETTLE_CYCLES(4),.CAM_RETRY_CYCLES(1)) retry_one(
    .clk100(clk),.btnC(button),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_sioc(scl_one),.cam_siod(sda_one),.cam_rst_n(reset_one),.uart_txd(tx_one),.led(led_one));
  defparam retry_off.config_camera.QUARTER_CYCLES=2;
  defparam retry_off.config_camera.POWER_WAIT=4;
  defparam retry_off.config_camera.REG_WAIT=3;
  defparam retry_one.config_camera.QUARTER_CYCLES=2;
  defparam retry_one.config_camera.POWER_WAIT=4;
  defparam retry_one.config_camera.REG_WAIT=3;

  always @(posedge clk)begin
    #1;
    if(retry_one.rst)begin
      cycles=0;previous_reset=0;previous_error=0;saw_fault=0;last_error=-1;
    end else begin
      cycles=cycles+1;
      if(retry_one.config_error && !previous_error)begin
        if(scl_one!==1 || sda_one!==1)$fatal(1,"retry error before clean bus release");
        last_error=cycles;
        if(first_error<0)first_error=cycles;
      end
      if(previous_reset && reset_one===0)begin
        if(cycles-last_error!=1)$fatal(1,"one-cycle retry delay changed");
        if(scl_one!==1 || sda_one!==1)$fatal(1,"retry interrupted active SCCB transaction");
        retries=retries+1;
      end
      if(retry_one.camera_fault)saw_fault=1;
      if(saw_fault && !retry_one.camera_fault)$fatal(1,"fault disappeared during unsuccessful retry");
      if(tx_one!==1 || tx_off!==1 || retry_one.frame_id!=0 || retry_off.frame_id!=0)
        $fatal(1,"unconfigured camera launched a frame");
      previous_reset=reset_one;previous_error=retry_one.config_error;
    end
  end
  initial begin
    repeat(5)@(negedge clk);button=0;
    wait(retry_off.config_error);
    repeat(1000)@(negedge clk);
    if(!retry_off.config_error || !retry_off.camera_fault || !led_off[15] ||
       reset_off!==1 || scl_off!==1 || sda_off!==1 || retry_off.camera_retry_count!=0)
      $fatal(1,"disabled retry did not preserve failed/released state and visible fault");
    if(retries<3 || !led_one[15])$fatal(1,"short retry did not repeat or show fault");
    // Diagnostic-page fault remains visible even during physical camera reset.
    sw=16'h4000;repeat(4)@(negedge clk);
    if(!led_off[6] || !led_one[6])$fatal(1,"diagnostic fault page");
    sw=16'h5000;repeat(4)@(negedge clk);
    if(!led_off[6] || !led_one[6])$fatal(1,"readback diagnostic fault page");
    // Manual button still clears both supervisors and restarts initialization.
    button=1;repeat(25)@(negedge clk);
    if(retry_off.camera_fault || retry_one.camera_fault ||
       reset_off!==0 || reset_one!==0 || led_off[6] || led_one[6])
      $fatal(1,"manual reset failed to clear camera faults");
    button=0;wait(!retry_off.rst);wait(retry_off.config_error);
    repeat(5)@(negedge clk);
    if(!retry_off.camera_fault)$fatal(1,"manual restart did not attempt configuration");
    $display("PASS camera_retry disabled/one-cycle retry, released bus, sticky LEDs and manual reset");
    $finish;
  end
  initial begin #100000;$fatal(1,"camera retry timeout");end
endmodule
