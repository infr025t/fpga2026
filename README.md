# FPGA 视频处理工程

当前工程为 [stream_video_edge_20fps](stream_video_edge_20fps/README.md)：Basys 3＋OV7670_FIFO＋NT35510，独立完成 VGA 灰度显示或一次 3×3 Gaussian＋Sobel。RAW 为 640×480，EDGE 为 630×470，固定阈值 128。目录名保留，方便既有工具继续使用。

2026-10-31 已测程序约 22.51 fps；2026-11-01 用户确认写入 Flash 后断电重启可显示 RAW/EDGE。该程序保存在 `artifacts`。2026-11-01 收敛源码已通过仿真和完整实现，新候选放在 `artifacts/consolidated_20261101/`，自动硬件回归通过、用户确认两种模式动态显示正常，与已测 Flash 基线分开管理。[验证说明](stream_video_edge_20fps/docs/validation.md)区分历史硬件证据、当前源码检查和视觉观察。

仓库保留一个当前视频工程及原样的 `demo/`。旧低速工程和一次性实验可从 Git 历史追溯。日常入口见[工程说明](stream_video_edge_20fps/README.md)，接线见[接线与使用](stream_video_edge_20fps/docs/wiring_and_use.md)。

历史和未解决问题见[异常台账](stream_video_edge_20fps/docs/anomaly_register.md)，包含移动暗条纹、斜向刷新分界线及本轮复测异常。
