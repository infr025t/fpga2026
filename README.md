# FPGA2026：VGA 20fps 测试工程
当前工程为 [stream_video_edge_20fps](stream_video_edge_20fps/README.md)：Basys 3＋GYF-198 OV7670_FIFO＋TK040F1510/NT35510，640×480灰度视频或3×3高斯平滑＋Sobel边缘，实测约22.51fps。用户已确认20fps基本通过。本次保留当前测试实现与诊断功能，没有做代码收敛。

构建、下载、接线与开关见[工程说明](stream_video_edge_20fps/README.md)。已上板bit位于stream_video_edge_20fps/artifacts/lcd_top_snapshot.bit。均匀横纹已由用户确认与照明频闪有关，本轮暂不处理；动态斜向刷新界线尚未独立定位，不宣称无撕裂。

[stream_video_edge](stream_video_edge/README.md)保留上一版低速基线，约1.9fps；demo/保持原样。旧工程的入口、报告和bit不代表本次20fps工程，请勿混用。
