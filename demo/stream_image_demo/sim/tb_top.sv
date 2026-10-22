`timescale 1ns/1ps
module tb_top;
  reg clk=0;always #5 clk=~clk;
  reg btnC=1;reg[15:0]sw=1;
  tri1 scl,sda; tri cam_reset; reg pull_low=0;
  pullup(cam_reset); assign cam_reset=pull_low?1'b0:1'bz;wire tx,rclk,rrst,wen;wire[15:0]led;
  stream_top #(.W(16),.H(12),.UART_DIV(4),.START_DELAY(20),.CAM_RESET_CYCLES(10),.CAM_SETTLE_CYCLES(12))
    dut(.clk100(clk),.btnC(btnC),.sw(sw),.cam_data(8'b0),.cam_vsync(1'b1),.cam_href(1'b0),
    .cam_rst_n(cam_reset),.cam_sioc(scl),.cam_siod(sda),.cam_rclk(rclk),.cam_rrst_n(rrst),.cam_wen(wen),.uart_txd(tx),.led(led));
  initial begin
    repeat(5)@(negedge clk);btnC=0;
    wait(!dut.rst);
    if(cam_reset!==0)$fatal(1,"camera reset not asserted");
    wait(cam_reset===1); // External pullup must provide the high level.
    if(!dut.camera_config_rst)$fatal(1,"configuration starts before settling");
    @(negedge clk);pull_low=1;#1;
    if(cam_reset!==0)$fatal(1,"RST drives high instead of releasing");
    @(negedge clk);pull_low=0;
    wait(!dut.camera_config_rst);
    if(cam_reset!==1)$fatal(1,"reset did not release");
    wait(dut.tx_done);repeat(5)@(negedge clk);
    if(dut.frame_id!=1)$fatal(1,"first frame id");
    wait(dut.tx_done);repeat(5)@(negedge clk);
    if(dut.frame_id!=2)$fatal(1,"second frame id");
    btnC=1;repeat(25)@(negedge clk);
    if(cam_reset!==0 || !dut.camera_config_rst)$fatal(1,"button reset sequence");
    btnC=0;wait(!dut.camera_config_rst);
    if(cam_reset!==1)$fatal(1,"second reset release");
    $display("PASS top repeated synthetic acquisition processing transmission");$finish;
  end
  initial begin #5000000;$fatal(1,"top timeout");end
endmodule
