# FPGA 车牌视觉系统 v1.1

本工程把相机采集、流式图像处理、板端字符识别与 LCD 反馈整合在 Basys 3 上。正常运行由 FPGA 独立完成；PC 用于调试记录与整数参考核验。v1.1 在绿色 ROI 框版本上增加白字选择，蓝底白字牌面可复用现有分割、归一化和 CNN 链路。

| 模式 | 实体开关 | 功能 |
|---|---|---|
| RAW | SW4=0，SW3=0 | 640×480 原灰度视频 |
| EDGE | SW4=0，SW3=1 | Gaussian3 + Sobel3，630×470 边缘视频 |
| OCR | SW4=1 | 原灰度视频、实际定位绿框、英数字识别结果 |

**OCR 字体极性：SW5=0 识别暗字（默认）；SW5=1 识别白字（蓝底白字场景）。** SW5 不改变 RAW/EDGE 画面，人工上传仍使用协议自己的 flags。原理、五帧同图对照和验证状态见[白字支持](docs/reference/white_character_support.md)。

SW2 保留不用。正常运行将 SW0、SW1、SW12、SW13、SW14、SW15 置0，并解除 VIO 覆盖；详见[接口与操作](docs/reference/interfaces_and_operation.md)。本版已写入 QSPI Flash，并验证从 Flash 重新加载后视频正常推进；JP1 保持 QSPI 可上电自启动。详见[Flash 与启动](docs/reference/flash_and_startup.md)。

| 目录 | 内容 |
|---|---|
| [project](project) | RTL、约束、模型、PC工具、仿真和构建入口 |
| [docs](docs/reference/index.md) | 完整中文架构、原理、数据、模型、操作和异常资料 |
| [release](release) | BIT 及配套 LTX；具体版本和验收身份见当前验证页 |
| [evidence](evidence) | 冻结源码、工具报告、板测原始数据和历史来源身份 |

程序入口：[`autonomous_board.bit`](release/autonomous_board.bit)。v1.1 的构建、下载和测试结果以[当前验证](docs/reference/current_validation.md)为准；旧 engineering_03 指标作为 v1.0 基线保留。

当前蓝底白字AL67L8实机连续20次输出一致，120字符、92,160个归一化像素和4,320个CNN分数全部与整数参考一致。100 MHz实现WNS +0.175 ns、WHS +0.017 ns；仅增加19 LUT、6 FF，BRAM/DSP不增加。原白底黑字整链回归也已通过。完整数据与适用条件见[当前验证](docs/reference/current_validation.md)。

建议从[系统报告](docs/system_report.md)阅读整体成果，再按[资料索引](docs/reference/index.md)进入原理、资源、复现或异常证据。
