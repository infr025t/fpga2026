# fpga2026 V0.3：VGA灰度与边缘检测

当前工程入口：[stream_video_edge](stream_video_edge/README.md)。Basys 3＋GYF-198 OV7670_FIFO；640×480采集，单次引导滤波或3×3高斯加权平滑后接Sobel，输出RAW灰度／EDGE边缘图。PC串口用于调试；NT35510屏幕驱动和像素接口保留。

已合入独立WRST、AL422预取字节计数及VSYNC短脉冲判定。自动曝光、增益开启时的50张移动／遮挡／补光验收通过；本次整理后的重新构建和回归结果见[验证报告](stream_video_edge/reports/validation.md)。WRST现接Basys3 JB1，不能继续使用WRST接VSYNC的旧说明。

`demo/`原样保留，仅供历史参考，其接线及分辨率不代表当前工程。本版为`V0.3 edge stable`，基于main提交`2b7f9d6`整理；源码、构建产物、接线说明和验收记录统一保存在`stream_video_edge/`。
