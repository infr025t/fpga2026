# v1.1 资源、时序与吞吐

当前数据对应 `white_characters_01`，目标XC7A35T-1、Vivado2025.1、系统100 MHz。[实现身份](../../evidence/blue_polarity/implementation.json)绑定[冻结源](../../evidence/implementation/white_characters_01/sources/manifest.json)；旧版完整资源分析见[v1.0归档](../archive/v1_0_resource_and_timing.md)。

## 实际资源与增量

| 项目 | v1.1 routed | v1.0 routed | 变化 |
|---|---:|---:|---:|
| 总LUT | 15612 | 15593 | +19 |
| Logic LUT | 14085 | 14066 | +19 |
| LUTRAM | 1492 | 1492 | 0 |
| SRL | 35 | 35 | 0 |
| FF | 18901 | 18895 | +6 |
| RAMB36 / RAMB18 | 40 / 9 | 40 / 9 | 0 |
| BRAM36等效 | 44.5 / 50（89%） | 44.5 / 50 | 0 |
| DSP | 9 | 9 | 0 |

[层次资源报告](../../evidence/implementation/white_characters_01/utilization.rpt)。ROI模块仍为64 LUT、62 FF，0 BRAM、0 DSP。增量为整机实现差，不把综合映射差异全部归为单个开关逻辑的理论开销。

白字功能复用分割器和归一化器已有的flags[1]，由识别子系统锁存并分发，未增加另一份图像RAM、卷积器或模型。视频仍用Gaussian三行8位灰度约1920 B、Sobel三行16位数据约3792 B；OCR保留160×120小图19200 B，按5个4096 B bank实现。LCD像素队列64 B。CNN串行复用算术单元及两块2048 B工作RAM，模型binary29128 B；详细布局见[模型资料](model_and_training.md)。

## 时序与约束

[时序报告](../../evidence/implementation/white_characters_01/timing.rpt)WNS +0.175 ns、WHS +0.017 ns，TNS/THS=0。首轮布局布线通过，无需refine。当前[DRC](../../evidence/implementation/white_characters_01/drc.rpt)41项Warning，0 Error/Critical Warning；[check_timing](../../evidence/implementation/white_characters_01/check_timing.rpt)无无时钟或无约束内部端点。外部输入预算、异步输入处理及告警细目集中在[异常台账](anomaly_register.md)。

## 当前实测调度

蓝底白字AL67L8的20个完整结果共120字符，源帧起始节拍22.507761 fps，OCR结果5.627032 fps。采集开始至结果平均153.060832 ms，单字符CNN9.42444 ms。[原始统计](../../evidence/blue_polarity/board_white_20/metrics.json)由FPGA时间戳计算。

视频连续推进，OCR忙时跳过新源帧并保留当前小图；两者不共用逐像素反压。识别一帧所需时间随候选字符数变化。这里区分源帧节拍、识别结果节拍和屏幕扫描刷新，后者不是本次时间戳测量对象。
