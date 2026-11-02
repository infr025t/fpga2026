`timescale 1ns/1ps
// OV7670上电/配置/预热时序。只处理驱动准备状态，不决定视频或识别模式。
// 场景选择在复位保持期间采样，避免运行中直接改寄存器形成半帧配置。
module camera_startup #(
 parameter integer RESET_CYCLES=1000000, CONFIG_CYCLES=2000000, WARMUP_CYCLES=200000000
)(input wire clk,rst,scene_request,config_done,config_error,
 output wire camera_reset_low,config_reset,camera_ready,output reg config_scene=1);
 reg[21:0]power_count=0;
 reg[27:0]warmup=0;
 assign camera_reset_low=rst||power_count<RESET_CYCLES;
 assign config_reset=rst||power_count<CONFIG_CYCLES;
 assign camera_ready=config_done&&!config_error&&warmup==WARMUP_CYCLES;
 always @(posedge clk)begin
  if(rst)begin power_count<=0;warmup<=0;config_scene<=1;end
  else begin
   if(power_count<CONFIG_CYCLES)power_count<=power_count+1'b1;
   if(power_count<RESET_CYCLES)config_scene<=scene_request;
   if(!config_done)warmup<=0;else if(warmup<WARMUP_CYCLES)warmup<=warmup+1'b1;
  end
 end
endmodule
