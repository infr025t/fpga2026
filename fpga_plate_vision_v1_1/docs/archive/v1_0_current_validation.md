# 当前发布版验证

当前发布采用 engineering_03 的绿色 ROI 框构建，用户已确认绿框可见、位置基本正确并接受当前显示效果。验证覆盖源身份、关键仿真、布局布线、实际板端输出和人工显示观察；各层证据共同支撑这套板端视频与识别系统的运行。

## 发布文件和源身份

| 项目 | 当前值或证据 |
|---|---|
| BIT | [release/autonomous_board.bit](../../evidence/history/v1_0_release/autonomous_board.bit) |
| BIT SHA256 | `8d2d8ed5c144a5d1618daad8c18fdd1ae9c5a99fb4e24623f98238f58167efae` |
| 配套 LTX | [autonomous_board.ltx](../../evidence/history/v1_0_release/autonomous_board.ltx) |
| 冻结源 | [sources/manifest.json](../../evidence/implementation/sources/manifest.json) |
| 实现身份与保护源比较 | [implementation.json](../../evidence/validation/roi_tolerance_probe/implementation.json)、[protected_sources.json](../../evidence/validation/roi_tolerance_probe/protected_sources.json) |
| 当前 RTL | 40 个模块，每模块一文件；ROI 显示独立为 `plate_roi_overlay` |
| 权重 | 冻结 gray 36 类模型，模型与识别数学沿用已验证版本 |

源码组织把驱动、视频、识别、调试和公共单元分层；PC 观察工具按协议、采集、组帧和验证拆分。绿色框由显示支路渲染，定位、分割和 CNN 继续使用其实际输入与既定规则。

## 仿真与软件核验

| 检查对象 | 结果和覆盖 | 原始证据 |
|---|---|---|
| PC 拆分 | 61 项测试通过；旧 wire 100 组、700 字符回放保持对应输出 | [测试日志](../../evidence/validation/pc_refactor/after_all_tests.log)、[回放比较](../../evidence/validation/pc_refactor/replay_comparison.json) |
| 模式和任务所有权 | RAW/EDGE 关闭自主识别，退出 OCR 取消旧任务，重入重采；人工/诊断优先 | [模式日志](../../evidence/logs/mode_transition.log) |
| 自主完整链 | 真实定位、分割、归一化、CNN；检查显示 ROI、空白帧撤框和忙时跳源帧 | [完整链日志](../../evidence/logs/roi_auto_final_simulate.log)、[串口参考核验](../../evidence/logs/roi_auto_final_uart_verify.log) |
| LCD 实际写事务 | 三帧共 910,500 个 RGB565 像素；颜色、尺寸、帧中更新及原像素 CRC | [逐像素日志](../../evidence/logs/roi_green.log) |
| ROI 边界 | VGA 边界、半开坐标、最小框、非法坐标、禁用/重入、复位和帧原子提交 | [边界日志](../../evidence/logs/roi_bounds.log) |
| 采集失败撤框 | 通过旁路失效事件在后续帧边界清除旧框 | [回归日志](../../evidence/logs/roi_abort_green.log) |
| 人工/兼容识别链 | 人工两帧、1,536 像素、72 分数；固定 ROI 链保留兼容性 | [人工日志](../../evidence/logs/engineering_manual_simulate.log)、[固定 ROI 日志](../../evidence/logs/engineering_fixed_roi_simulate.log) |

完整链测试使用真实工作模块；黄金数据用于比较输出。显示测试在 LCD 写事务处重建 RGB565 像素，因此覆盖坐标和总线数据交付。人工屏幕观察另由用户反馈记录。

## 100 MHz 实现

最终 WNS **+0.029 ns**、WHS **+0.050 ns**，TNS/THS 均为0。顶层使用 **15,593 LUT、18,895 FF、40 RAMB36、9 RAMB18、9 DSP**。ROI 模块为64 LUT、62 FF，无 BRAM、DSP。

初次布线 WNS −0.069 ns、TNS −0.091 ns；按既有物理优化流程完成收敛，RTL 和约束不变。初次与最终报告同时保留在 [implementation](../../evidence/implementation)。精确资源和时序解释见[资源页](../reference/resource_and_timing.md)，约束与工具告警明细见[异常台账](../reference/anomaly_register.md)。

## 发布版本板上结果

[10 组采集](../../evidence/validation/roi_board_10/summary.json)与[FPGA 时间戳统计](../../evidence/validation/roi_board_10/metrics.json)给出：

| 指标 | 结果 |
|---|---:|
| 完整组 / 与整数参考一致 | 10 / 10 |
| 字符数 | 70 |
| 归一化像素 / 不一致 | 53,760 / 0 |
| CNN 有符号分数 / 不一致 | 2,520 / 0 |
| 源帧起始节拍 | 22.507753 fps |
| OCR 结果节拍 | 5.626485 fps |
| 采集开始至结果平均 | 165.861397 ms |
| 单字符 CNN | 9.42444 ms |
| bad_captures / publisher_dropped 最大值 | 0 / 0 |

LCD 数字状态为 received=painted=307200，输入/出队 CRC 一致；用户确认绿色区域框显示。输出与真实牌面之间的整串评分，以及前缀候选现象，统一列在[验证数据](../reference/validation_data.md)，避免把实现一致性写成识别准确率。

[下载日志](../../evidence/logs/roi_program_console.log)记录 RAM 配置；[physical 日志](../../evidence/logs/roi_physical_console.log)记录解除 VIO 覆盖，控制交回实体开关。当前 Flash 沿用旧程序。

## 与前一构建的关系

engineering_02 是三模式整理后的不带框版本，保留100组实机数据；当前 engineering_03 增加实际定位框。其详细过程归档为[engineering_02 验证](../archive/engineering_02_validation.md)。本次发布以当前 BIT 和当前10组数据为主；旧100组用于理解算法行为和对照版本，历史 BD12345 成绩按原场景单独列示。


## 发布目录中的再验证

工程移入四目录结构后，再次完成40模块结构门禁、47个保护源字节核验、49项冻结清单和发布BIT/LTX身份核验，见[发布结构检查](../../evidence/release_checks/engineering_structure.json)。工具入口的可移植化检查包括61项PC测试、11项离线工具检查及32份PowerShell脚本语法解析，记录见[PC测试](../../evidence/release_checks/tooling/pc_unittest.log)、[工具检查](../../evidence/release_checks/tooling/tooling_checks.json)和[PowerShell检查](../../evidence/release_checks/tooling/powershell_checks.json)。

保存的当前ROI版10组wire在发布目录中重新回放，10组、70字符全部与整数参考一致，见[发布目录回放](../../evidence/release_checks/roi_wire_replay/summary.json)。该检查验证移动后的路径、模型加载、协议解析和参考链路；使用的是已保存的同一批板端数据。

发布目录还重新执行了四组 Vivado 仿真：ROI 边界与帧内稳定性、采集中止与模式切换、LCD 总线逐像素检查，以及自主识别整链。LCD 检查覆盖 910,500 个 RGB565 像素；整链完成七字符与空白帧场景，串口结果的 5,376 个归一化像素和 252 个有符号分数与参考全部一致。新运行日志及汇总见[发布验证汇总](../../evidence/release_checks/verification_summary.json)。本轮保存原验收 BIT，硬件实现文件、模型与约束均未改变。
