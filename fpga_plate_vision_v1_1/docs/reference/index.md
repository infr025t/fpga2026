# 发布版资料索引

本资料围绕三个工程成果展开：连续视频的行缓存处理、独立运行的板端识别链，以及从实际引脚事务到整数参考的可复核验证。v1.1 在绿色 ROI 版本上增加 SW5 白字选择；engineering_03 保留为 v1.0 基线，当前构建与板测身份见验证页，发布文件位于根目录 `release/`。

| 文档 | 内容 |
|---|---|
| [白字支持](white_character_support.md) | 蓝底白字问题、最小改动、SW5操作、同图证据和适用条件 |
| [系统报告](../system_report.md) | 设计目标、关键贡献、系统工作过程与发布成果 |
| [架构](architecture.md) | 模块层次、流式视频与小图 OCR 协作、内存和所有权 |
| [算法原理](algorithm_principles.md) | 高斯/Sobel、定位、分割、粘连拆分、归一化和整数 CNN |
| [Flash与启动](flash_and_startup.md) | Flash型号、安装证据、自启动与烧录复现 |
| [接口与操作](interfaces_and_operation.md) | 接线、RAW/EDGE/OCR、暂停、串口、JTAG 与 Flash 状态 |
| [区域显示](roi_overlay_and_options.md) | 实际定位框、坐标映射、帧边界提交与显示验证 |
| [PC 工具](pc_tools.md) | 协议、采集、组帧、整数参考及回放 |
| [工程与复现](engineering_and_reproduction.md) | 四目录组织、构建、源冻结与验证入口 |
| [当前验证](current_validation.md) | 发布身份、仿真、实现与当前板上证据 |
| [验证数据](validation_data.md) | 当前及历史评分、分母、参考一致性与识别效果 |
| [模型与训练](model_and_training.md) | 36 类模型、量化、数据划分、训练与保存指标 |
| [资源与时序](resource_and_timing.md) | 当前占用、时序、存储结构、视频/OCR速率 |
| [异常台账](anomaly_register.md) | 完整历史异常及发布版追加，保留原因证据与处理状态 |
| [历史证据](historical_evidence.md) | 阶段、原件身份及历史结论来源 |
| [扩展路线](limitations_and_next_steps.md) | 基于当前模块边界的评估和改进任务 |

## 发布身份与取材规则

[实现记录](../../evidence/validation/roi_tolerance_probe/implementation.json)、[冻结源码](../../evidence/implementation/sources/manifest.json)、[板测原始记录](../../evidence/validation/roi_board_10/summary.json)共同标识 v1.0 engineering_03 基线。v1.1 的白字变更与新增证据见[白字支持](white_character_support.md)及[当前验证](current_validation.md)。[迁移清单](../../evidence/migration_manifest.json)、[数据来源](../../evidence/data_sources.json)、[异常来源](../../evidence/anomaly_sources.json)保留历史身份。

报告引用使用“版本、场景、样本分母、评价方法、原始证据”五项信息。硬件与整数参考一致、整串真值正确、视频输入节拍、OCR 结果节拍各有独立定义。历史材料集中存放在 `docs/archive/` 和 `evidence/baseline/`；其中早期计划描述当时的任务，不改变当前发布状态。
