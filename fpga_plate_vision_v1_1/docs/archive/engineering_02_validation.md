# 本轮工程整理验证记录

本页只记录新工程实际执行。历史统计见[历史数据](../reference/validation_data.md)，不得移作本轮板测。用户已确认三个模式为RAW、EDGE、OCR；SW4优先OCR，SW4=0时SW3选EDGE/RAW。

## 源代码与行为边界

源目录 `project`；原目录只读。39个模块/39个文件经[结构检查](../../evidence/validation/engineering_structure.json)通过，34个保护模块计算与状态逻辑去注释空白后与基线一致，模型哈希未变。顶层提取startup/pattern，CNN权重ROM单独成文件；新增模式译码与OCR任务门控。PC拆分61项测试及旧wire回放见[拆分记录](../../evidence/validation/pc_refactor/commands.md)。这不意味着仅改文件名：新增三模式是明确的功能变更。

## 已完成离线检查

| 检查 | 实际结果 | 证据 |
|---|---|---|
| 结构/保护实现 | 39模块，34保护模块不变，模型不变 | [JSON](../../evidence/validation/engineering_structure.json) |
| PC单元测试 | 61项通过 | [日志](../../evidence/validation/pc_refactor/after_all_tests.log) |
| 新旧PC回放 | 同一旧wire100组、700字符；除运行耗时/来源描述外对应输出相同 | [比较](../../evidence/validation/pc_refactor/replay_comparison.json) |
| startup/pattern提取 | 缩短计数下逐周期对照；完整VGA307200像素，CRC f9824a15 | [日志](../../evidence/history/plate_recognition_engineering/build/sim_controls/controls.log) |
| 三模式任务所有权 | RAW/EDGE禁用OCR；半帧退出取消，重入重采；人工及诊断优先 | [日志](../../evidence/history/plate_recognition_engineering/build/sim_mode/modes.log) |
| 动态定位/切分自主整链 | 真工作模块，7字符与空白帧、忙时跳源帧 | [日志](../../evidence/logs/engineering_auto_simulate.log) |
| 自主串口仿真 | 13包45832字节，5376归一化像素、252分数及CRC/框/文本一致 | [日志](../../evidence/logs/engineering_auto_uart_verify.log) |
| 人工串口实际整链 | 两帧，1536归一化像素、72分数、2464响应字节，模式切换 | [日志](../../evidence/logs/engineering_manual_simulate.log) |
| 固定ROI兼容链 | 7字符与空白帧、跳源帧，输入和源哈希稳定 | [日志](../../evidence/logs/engineering_fixed_roi_simulate.log) |
| LCD写引脚仿真 | 603300个RGB565像素检查；RAW/EDGE、气泡、文字帧原子性、源CRC | [日志](../../evidence/logs/engineering_lcd_text.log) |

模式测试未穷举所有顶层切换相位。归一化旧原始向量输入在基线就缺失，当前runner可校验并沿用冻结向量；只验证前置选择，不声称本轮重复全部旧单元仿真。迁移路径与夹具修复细节见[回归入口修复](../../evidence/validation/regression_paths/report.md)。

自主与人工整链完成后，仅把ov7670_config旧Y_BYTE=1注释纠正为当前采集默认Y_BYTE=0；逻辑未变。仿真源哈希保留其当时身份，最终BIT使用冻结源码清单，不伪改旧测试清单。

## 本轮遇到并修正的问题

| 编号 | 问题/证据 | 原因与处理 | 验证状态 |
|---|---|---|---|
| E01 | 中文PowerShell脚本解析失败 | Windows PowerShell默认解码与无BOM UTF8不兼容；统一UTF8 BOM | 相应runner实际通过 |
| E02 | 中央列表编译顶层时信号前向声明冲突 | 识别实例位于后续声明前；移到声明后，未改连接 | 完整编译与仿真通过 |
| E03 | 旧固定ROI测试缺recognition_enable，旧向量路径缺失 | 新端口补1；迁移路径修正，复制54份原夹具并SHA核对 | 固定ROI整链通过，16份生成向量数值不变 |
| E04 | build/engineering_01综合失败：lcd_vio not found | 整理脚本省略synth_ip导致IP未解析；恢复原IP综合步骤 | 失败日志保留；后续build/engineering_02单独验收 |

E04失败证据：[build01日志](../../evidence/history/plate_recognition_engineering/build/engineering_01/build.log)。失败版本没有有效新BIT，未下载到板卡。以上是整理过程问题，与旧相机拼接根因不能混写。

## 实现与硬件状态

新构建`build/engineering_02`已成功生成BIT，build.ps1退出0，日志末尾为`PASS AUTONOMOUS_BOARD_BUILD`。本轮首次有效布线即通过，不需要额外物理优化。详见[实现身份](../../evidence/validation/implementation.json)、[时序](../../evidence/history/plate_recognition_engineering/build/engineering_02/timing.rpt)、[资源](../../evidence/history/plate_recognition_engineering/build/engineering_02/utilization.rpt)。

| 项目 | 本轮整理版 | 历史build_split最终值 |
|---|---:|---:|
| LUT | 15,599 | 15,587 |
| FF | 18,832 | 18,829 |
| RAMB36 / RAMB18 | 40 / 9 | 40 / 9 |
| BRAM36等效 | 44.5 / 50，89% | 44.5 / 50，89% |
| DSP | 9 | 9 |
| WNS / WHS | +0.185 / +0.024 ns | +0.088 / +0.006 ns |
| TNS / THS | 0 / 0 | 0 / 0 |

LUT增加12、FF增加3，BRAM和DSP未增加；差异包含结构重组、模式门控和工具映射，不能分摊为某一个模块的实测成本。时序裕量改善是此次实现结果，不证明换布局或改算法后必然保持。

BIT SHA256：`91a6e3db556cf55dc619506cd091577f5fbe39bfabc79c5a7532153869584741`。LTX及48项冻结源身份见实现JSON；当前RTL、模型、约束与冻结副本全部相符。

DRC有41项普通Warning，Error和Critical Warning为0；这**不等于整个构建日志没有Critical Warning**。日志保留两类：`synth_ip`在project模式的兼容提示（随后实际IP综合成功），以及原有RCLK datapath约束的路径分段提示。check_timing仍列13个已有false-path的无input-delay输入、8个相机数据partial-input-delay；内部未约束端点为0。约束未放宽，外部采样预算仍不代替实测电气裕量。这些事项留作后续工具流程和约束审查，不隐藏在“时序通过”中。

[下载日志](../../evidence/logs/program_engineering_02_console.log)确认新BIT已配置到Basys3 RAM，随后开始三模式实机检查。未写Flash；本轮实拍结果见下节。

[板卡探测](../../evidence/logs/board_probe_console.log)已发现Basys3目标210183BCBF83A；只探测不能证明新程序已下载或识别有效。该探测本身没有更改程序；之后配置RAM的动作单独记录。旧Flash和旧仓库保持不变。

## 本轮板上模式与实拍

[模式数字观测](../../evidence/validation/display_modes.json)通过：RAW、EDGE、内部RAW图、OCR各读取两次，帧计数均继续增长。RAW/OCR每帧received=painted=307200，EDGE为296100，源输入/出队CRC一致；内部RAW CRC为f9824a15；所有样本status_error和reference_failures为0。RAW、EDGE和内部图模式的自主识别状态清零。此项是JTAG数字状态与计数核查，没有独立光学检查每个LCD像素，也未穷举实体开关抖动的所有相位。

[10组预检](../../evidence/validation/engineering_precheck_10/summary.json)全部符合参考、共77字符。场景已不是历史BD12345，而是用户本轮确认的K38817，因此不能复用历史正确率。

[100组正式记录](../../evidence/validation/engineering_board_100/summary.json)与[计时统计](../../evidence/validation/engineering_board_100/metrics.json)：

| 指标 | 实际结果 |
|---|---:|
| 完整结果/参考一致 | 100 / 100 |
| 比较字符 | 800 |
| 归一化像素/不一致 | 614400 / 0 |
| CNN分数/不一致 | 28800 / 0 |
| 用户确认整串K38817正确数 | **0 / 100** |
| 实际输出 | WGK38817 65次；MGK38817 35次 |
| 末尾六字符匹配 | 100 / 100，仅诊断，不算整串正确 |
| bad_captures / publisher_dropped最大值 | 0 / 0 |
| 接收残缺组/CRC候选拒绝/尾截断字节 | 1 / 0 / 240 |
| 源frame_id首/末 | 2846 / 3341，连续识别间隔均5源帧 |
| 源帧起始节拍 | 22.507754 fps |
| OCR结果节拍 | 4.501570 fps |
| 采集开始到结果平均 | 180.1293 ms |
| 单字符CNN | 9.42444 ms |

该100组位于一次连续接收窗口，无串口异常或超时；开头从任意包中途加入，保留590丢弃字节和1个首部不完整组，收尾240字节也保留。不能称全部USB字节零丢失。busy期间主动跳过4源帧再接纳下一帧是当前8候选工作量的调度结果；与历史7候选约5.63fps的场景不同，不能直接归因于重构降低识别性能。

## 新确认的算法问题：汉字/边框误纳入

[诊断数据](../../evidence/validation/engineering_board_100/scene_failure_analysis.json)、[第一帧分割图](../../evidence/validation/engineering_board_100/segmentation_failure.png)。首帧frame2846的ROI为[12,29,151,80)，宽139；左1/8排除线x=29。多余框为(16,36,34,39)和(24,42,13,27)，中心x分别33与30.5，均越过排除线而被保留。图中第一框覆盖左侧边框及字符附近，第二框为汉字区域；后六框为K38817。位置排除规则没有识别汉字能力，实际保留这两个候选是可复现的算法缺陷。

用户也报告放置范围仍苛刻；本轮没有位置网格扫测，故只记录定性反馈及当前摆放失败样例，不虚构允许偏移量。此问题并非本轮“已修复”：完整组在RTL与原整数模型上一致，保护算法也未变，下一步应单独优化前端并用独立牌号/位置集验证。

## 最终运行与整理结论

已用[physical动作](../../evidence/logs/physical_control_console.log)清除VIO覆盖，交还实体开关；未写Flash。SW4=1进入OCR，SW4=0时SW3选RAW/EDGE。断电重新上电仍可能加载旧Flash版本和旧开关定义。

工程整理通过本轮结构、PC、关键整链仿真、实现和板上数字一致性检查；**识别算法的场景适用性仍未达标**，不得称整体识别功能验收通过。现有模式接口和模块边界可用于下一轮优化。旧目录3338个迁移来源文件与迁移时哈希全部一致，见[基线保护](../../evidence/validation/baseline_preservation.json)。本轮无Git推送、无打包。
