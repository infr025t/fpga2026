# v1.1 发布验证

当前发布构建为 `white_characters_01`，已完成100 MHz实现、RAM下载和当前蓝底白字场景的20次自主识别。原v1.0证据见[归档验证](../archive/v1_0_current_validation.md)。

## 程序身份与范围

[发布清单](../../release/release_manifest.json)绑定BIT、LTX与[53项冻结源](../../evidence/implementation/white_characters_01/sources/manifest.json)。BIT SHA256为 `bdca082ba4c9cdc444a718e6fcab103cfb06e8b6b728281e0741615015b1ed0e`。

本次只修改顶层与识别子系统两份RTL。相机、FIFO、显示、定位、分割、归一化、CNN等其余38份RTL以及模型、约束均逐字节不变；新增连接调用既有反相功能，见[变更审计](../../evidence/blue_polarity/source_change_audit.json)。

## 软件与仿真

| 项目 | 结果 |
|---|---|
| PC回归 | 61项通过 |
| 极性切换 | 中止半帧、保留原字节、锁存flags=2、撤销旧ROI通过 |
| 白字自主整链 | AL67L8；6字符、4608归一化像素、216分数精确一致；空白帧撤框通过 |
| 暗字自主回归 | BD12345；7字符、5376像素、252分数精确一致 |

日志与UART逐包回放见[仿真汇总](../../evidence/blue_polarity/simulation_summary.json)。[独立代码审查](../../evidence/blue_polarity/review.md)检查了极性锁存、复位边界、人工模式与遥测语义。

## 布局布线

Vivado2025.1、XC7A35T-1、100 MHz，WNS **+0.175 ns**、WHS **+0.017 ns**，TNS/THS为0。顶层15612 LUT、18901 FF、40 RAMB36、9 RAMB18、9 DSP；相对v1.0增加19 LUT、6 FF，不增加BRAM/DSP。本次首轮实现通过时序，无需追加refine步骤。[实现记录](../../evidence/blue_polarity/implementation.json)、[时序](../../evidence/implementation/white_characters_01/timing.rpt)、[资源](../../evidence/implementation/white_characters_01/utilization.rpt)。

## 当前蓝底白字板测

| 指标 | 实测 |
|---|---:|
| 完整识别组 / 参考一致 | 20 / 20 |
| 输出AL67L8 | 20 / 20 |
| 字符 | 120 |
| 归一化像素 / 不一致 | 92160 / 0 |
| 有符号分数 / 不一致 | 4320 / 0 |
| 源帧起始节拍 | 22.507761 fps |
| OCR结果节拍 | 5.627032 fps |
| 采集开始至结果平均 | 153.060832 ms |
| 单字符CNN时间 | 9.42444 ms |
| bad_captures / publisher_dropped | 0 / 0 |

[20组原始数据](../../evidence/blue_polarity/board_white_20/summary.json)、[时间戳统计](../../evidence/blue_polarity/board_white_20/metrics.json)。AL67L8由本轮保存图像人工读出，用户确认已对准但未另行输入号码；[评分来源](../../evidence/blue_polarity/scoring_context.json)与预测分开。20/20描述同一静态牌面下的重复结果。帧率来自100 MHz FPGA时间戳，LCD扫描刷新未作独立光学测量。

本轮用户不方便查看屏幕，未新增屏幕目视确认。[下载日志](../../evidence/blue_polarity/program.log)与[解除VIO日志](../../evidence/blue_polarity/physical.log)记录了RAM下载和交回实体开关；随后按用户要求将同一BIT写入Flash并校验。从QSPI重新加载后，1.5秒采样间隔内视频帧计数增加34，错误码0，匹配VIO已加载；本轮没有人工断电重启或新增屏幕目视验收。见[Flash安装记录](../../evidence/flash_install/installation.json)与[启动日志](../../evidence/flash_install/boot_verified.log)。

## 使用与复核

SW4=1进入OCR：SW5=0暗字、SW5=1白字；正常相机运行其他诊断开关置0。见[操作表](interfaces_and_operation.md)。原始灰度、绿框与三模式显示路径保持不变。完整机制及适用条件见[白字支持](white_character_support.md)，历史前缀问题继续单独见[验证数据](validation_data.md)。
