# FPGA2026：V0.4 LCD RAW／EDGE
当前工程在stream_video_edge/：Basys3＋GYF-198 OV7670_FIFO＋TK040F1510/NT35510，独立完成VGA灰度读取、一次平滑和Sobel，完整尺寸送LCD。主入口lcd_top，使用build_lcd.ps1/program_lcd.ps1；接线、开关与验证见[工程说明](stream_video_edge/README.md)。
本轮收敛低速2MHz链路，约1.9fps；没有实现20fps。两种EDGE传输动态检查正常，高斯边缘效果仍待调参。全部相机线缩短是本次硬件条件，不能单独归因于RCK。
原串口调试入口和V0.3历史bit保留，勿与LCD入口混用。demo/原样保留。后续高速方案仅为计划。
