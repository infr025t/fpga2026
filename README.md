# FPGA 车牌视觉系统

当前发布为 [fpga_plate_vision_v1_1](fpga_plate_vision_v1_1/readme.md)：Basys 3＋OV7670_FIFO＋NT35510，独立完成 VGA 灰度视频、Gaussian＋Sobel 边缘视频和英数字车牌识别。识别包含小图定位、字符分割、归一化、整数 CNN，LCD 显示定位绿框及识别文字；PC 仅用于调试和参考校验。v1.1 增加白字选择，支持本次验证的蓝底白字场景。

SW4=0 时 SW3=0 为 RAW、SW3=1 为 EDGE；SW4=1 为 OCR，SW5=0 为暗字、SW5=1 为白字。本版已写入 QSPI Flash 并通过校验，从 QSPI 重新加载后视频计数正常推进；JP1 保持 QSPI 用于上电自启动。[接口与操作](fpga_plate_vision_v1_1/docs/reference/interfaces_and_operation.md)及[Flash 与启动](fpga_plate_vision_v1_1/docs/reference/flash_and_startup.md)给出具体步骤。

发布包内 `project/` 放代码，`docs/` 放原理、数据及操作文档，`release/` 放 BIT/LTX/MCS，`evidence/` 放原始验证记录。源码、构建产物与校验清单绑定，可运行 `python -B fpga_plate_vision_v1_1/project/scripts/verify_release.py` 复核。

本次蓝底白字板测20次输出一致，120字符的归一化像素及CNN分数与整数参考零差异；输入节拍约22.51 fps，OCR结果节拍约5.63 fps。具体场景、分母和证据见[当前验证](fpga_plate_vision_v1_1/docs/reference/current_validation.md)。[系统报告](fpga_plate_vision_v1_1/docs/system_report.md)、[资料索引](fpga_plate_vision_v1_1/docs/reference/index.md)和[异常台账](fpga_plate_vision_v1_1/docs/reference/anomaly_register.md)作为报告取材入口。

`demo/` 原样保留；[stream_video_edge_20fps](stream_video_edge_20fps/README.md)保留为之前的独立视频基线，其文档与 Flash 状态属于历史版本。当前入口统一以上述 v1.1 发布包为准。
