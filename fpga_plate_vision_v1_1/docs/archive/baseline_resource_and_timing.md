# 资源、时序与速率原始参考

## 状态：本页保留历史BASELINE，整理版结果见current_validation

本页的已测数字只属于历史 `historical/plate_autonomous_board_20261101/build_split`。本轮整理版 `build/engineering_02` 尚不能引用这些数字作为自身实现结果。新结果必须绑定新的 frozen source manifest、BIT、布局布线 timing/utilization、约束及实机记录；本页不预填新工程最终指标。

基线器件为 `xc7a35tcpg236-1`，顶层 `lcd_top`，Vivado v2025.1 win64 build 6140274，报告状态 Routed/Fully Routed。报告内时间为 2026-11-01 19:36 左右（工具本地时间，未另证时区）。

| 证据 | SHA256 |
|---|---|
| [基线 BIT](../../evidence/history/plate_autonomous_board_20261101/build_split/autonomous_board.bit) | `81e421b371d8b4d5b3e77757b87d8c9e67e1c3ab74dcd395e331a02284dd1297` |
| [timing_refined.rpt](../../evidence/history/plate_autonomous_board_20261101/build_split/timing_refined.rpt) | `bc739e8db3d0b39c8fb0cab28ad009131109a7f31abf7ec1b1a5c85e6467deea` |
| [utilization_refined.rpt](../../evidence/history/plate_autonomous_board_20261101/build_split/utilization_refined.rpt) | `3c1219ac263dc51fa8cf8f0d32a785cac7dc50be2e643558d3edbf4f4683eb01` |

来源关系见 [split_artifacts.json](../../evidence/baseline/reports/split_artifacts.json) 和 [冻结源 manifest](../../evidence/history/plate_autonomous_board_20261101/build_split/sources/manifest.json)。[data_sources.json](../../evidence/data_sources.json) 保存本次实际读取的上述文件、冻结源、模型与数据 SHA256。阶段 artifact 内的历史 hash 与本次实际文件已逐项比对，不用当前改动中的 RTL 反推旧报告。

## 资源口径

| BASELINE 顶层资源 | routed 用量 | 定义 |
|---|---:|---|
| Total LUTs | 15587 | 包含 Logic LUT、LUTRAM、SRL |
| Logic LUTs | 14060 | 逻辑用途 |
| LUTRAMs | 1492 | LUT 分布式存储用途 |
| SRLs | 35 | LUT 移位寄存器用途 |
| FF | 18829 | 寄存器 |
| RAMB36 | 40 | 36 Kb 原语数 |
| RAMB18 | 9 | 18 Kb 原语数 |
| 36 Kb 等效 BRAM tile | 44.5 | 40+9/2；不能把 40+9=49 当作 36 Kb tile |
| DSP Blocks | 9 | 整机统计，不是纯 CNN |

LUT 子项 `14060+1492+35=15587`。资源来自同一份 routed hierarchical report；不能混用综合前或初次布局后的另一份报告。表中没有用模型 29128 字节推导整机 RAM，也没有把整机资源等同于识别模块资源。

| BASELINE 实例（包含其子级） | Total LUT | FF | RAMB36 | RAMB18 | DSP |
|---|---:|---:|---:|---:|---:|
| recognition | 11550 | 9420 | 24 | 3 | 3 |
| recognition/automatic_observer | 2050 | 3313 | 0 | 0 | 0 |
| recognition/automatic_recognition | 1536 | 3232 | 0 | 0 | 0 |
| recognition/normalize_character | 2039 | 847 | 5 | 1 | 1 |
| display | 1193 | 995 | 0 | 0 | 3 |
| processing | 369 | 473 | 0 | 6 | 0 |
| camera | 368 | 629 | 0 | 0 | 0 |
| debug_bridge | 547 | 4766 | 0 | 0 | 0 |
| dbg_hub | 448 | 741 | 0 | 0 | 0 |

这些行只选取部分层级，且父子相互包含，**不可逐行相加**。尤其 VIO/debug hub 和 UART 观察路径已经计入顶层，不应作为“零调试开销”的系统数字。整理后的实例路径可以变化，旧层级名仅标识历史证据。

## 实现前后时序

| 阶段 | WNS ns | TNS ns | setup 失败端点 | WHS ns | THS ns | hold 失败端点 |
|---|---:|---:|---:|---:|---:|---:|
| build_split 初次 routed，timing.rpt | -0.330 | -0.837 | 4 | 0.006 | 0 | 0 |
| build_split refined，timing_refined.rpt | 0.088 | 0 | 0 | 0.006 | 0 | 0 |

初次结果是时序失败记录，必须保留；refined 使用既有物理优化流程，[refine_timing.tcl](../../evidence/history/plate_autonomous_board_20261101/scripts/refine_timing.tcl) 与 artifact 记录表明约束未放宽。refined 报告 setup 总端点 56319、hold 总端点 56258，WPWS=3.750 ns、pulse-width 失败端点 0。sys_clk 周期 10.000 ns（100 MHz）；另有 fifo_virtual 60.000 ns（16.667 MHz）和 debug TCK 33.000 ns（30.303 MHz）。虚拟时钟是约束对象，不能据此宣称相机像素时钟实测为 16.667 MHz。

WNS/WHS 是当前约束及工具角点下的最差 setup/hold slack，不是 OCR 延迟；正 slack 不是独立测得最高工作频率。0.088 ns setup 和 0.006 ns hold 裕量较小，应保留精确数值。新的顶层提取、名称或布局变化仍需重新实现，不能因逻辑等价而沿用裕量。

`check_timing` 记录 no_clock=0、unconstrained_internal_endpoints=0、loops=0、latch_loops=0，同时存在：

- 12 个无 input delay、但有用户 false path 的输入端口，MEDIUM。
- 8 个 partial_input_delay 输入端口，HIGH。

因此只能陈述“报告所指定时序约束均满足”，不能改写成“全部输入接口均已完整时序验证”。需结合冻结 XDC 中异步开关/控制路径及 FIFO 输入约束评审，不能为了消除提示无依据添加或放宽约束。

[DRC refined](../../evidence/history/plate_autonomous_board_20261101/build_split/drc_refined.rpt) 有 43 项 Warning：DPIP-1 8、DPOP-1 5、DPOP-2 5、DPOR-1 17、PDCN-1569 3、PLBUFGOPT-1 2、RPBF-3 2、RTSTAT-10 1。该报告摘要未列 Error/Critical Warning；不能称 DRC“零告警”。具体对象与细节应从原报告核查，本文不推断已被修复。

## 实机吞吐与延迟：三个不同指标

本节来源 [split_aligned_repeat_100/metrics.json](../../evidence/baseline/reports/split_aligned_repeat_100/metrics.json) 与 [计算脚本 summarize_auto.py](../../evidence/history/plate_autonomous_board_20261101/scripts/summarize_auto.py)。100 个完整结果、700 个字符，同一 BD12345 场景。原始计数来自 100 MHz FPGA 时间戳，不是 PC 程序运行时间，也不是光学测得 LCD 刷新。

| 指标 | BASELINE 值 | 含义 |
|---|---:|---|
| input_start_fps | 22.507769042448196 | 观测源帧号增量/FPGA capture tick 间隔 |
| observed_recognition_fps | 5.626956163353177 | 相邻完整识别结果完成平均时间间隔的倒数 |
| recognition_capture_fps | 5.626942260612049 | 被识别帧 capture tick 间隔的倒数平均 |
| capture_to_result 平均 | 161.7688653 ms | 单帧采集时间戳至识别结果完成 |
| capture_to_result 最小/最大 | 161.68508 / 161.77830 ms | 100 个完整结果范围 |
| segment 平均 | 43.3205377 ms | 结果记录 `seg_cycles`；包含相应前端调度范围 |
| segment 最小/最大 | 43.29029 / 43.32701 ms | 同上 |
| 单字符 normalize 平均 | 1.1496577142857143 ms | 700 字符的归一化周期平均 |
| 单字符 normalize 最小/最大 | 0.91006 / 1.27686 ms | 不同字符裁剪尺寸造成工作量不同 |
| 单字符 CNN | 9.42444 ms | 942444 周期；700 个字符一致 |

7 字符 CNN 时间总和约 65.97108 ms，但不能单独代表整帧延迟。capture_to_result 还包含采集、前端、归一化和调度；也不能把 `1/平均延迟` 当作实际 OCR fps，因为下一次识别还受源帧时刻和接纳策略影响。

令 `f_clk=10^8`、相邻同 epoch 的 capture tick 为 t_i、源帧号为 F_i、elapsed cycles 为 e_i。脚本只统计同 epoch、帧号正增且 dt 非零的相邻结果：

- `Δt_i=(t_(i+1)-t_i) mod 2^32`。
- `f_input = Σ(F_(i+1)-F_i) × f_clk / ΣΔt_i`。
- `f_capture = N_valid_intervals × f_clk / ΣΔt_i`。
- `Δr_i=(t_(i+1)+e_(i+1)-t_i-e_i) mod 2^32`，`f_result=N_valid_intervals × f_clk/ΣΔr_i`。
- `latency_ms=e_i/100000`；segment/norm/CNN 周期同样除以 100000。

32 位 100 MHz tick 约 42.94967296 s 回卷，脚本用逐相邻模差；相邻数据若跨多个完整回卷，单靠 32 位时间戳无法恢复真实时长。这一轮相邻间隔远小于该范围。fps 分母使用 99 个间隔，而不是 100 除首末时间。

视频源帧号 5249→5645 共跨 396 个源帧间隔，skipped_frames 3364→3661 增加 297，100 个识别帧之间 99 个间隔均跨 4 个源帧。bad_captures 和 publisher_dropped 在这批记录中均为 0；这说明记录到的计数范围，不代表无限时长零丢失。上一轮 [split_aligned_100](../../evidence/baseline/reports/split_aligned_100/metrics.json) 因完整结果有间断，观测结果率为 4.76125910 fps，不能用它反推 CNN 核心变慢。

`input_start_fps≈22.51` 表示系统中的源帧起始节拍；没有独立光电/高速相机测量 LCD 发光更新或像素响应，因此不可写“LCD 实测 22.51 fps”。`OCR≈5.63 fps` 才是该固定场景被观测到的识别结果节拍。8N1 标称 12 Mbaud 串口有效字节率理论上界约 1.2 MB/s，尚未扣除协议开销、间隔或丢失；标称串口速率不是 OCR 吞吐。

## 整理版追加要求

待新工程完成真实实现后，单独列新 BIT/source/约束/模型哈希、工具版本、实际资源、初次及最终时序、DRC/约束残留事项。待实机采集后另列实际场景和上述统一计数定义；原 baseline 表应保留。若只有仿真或离线 wire 回放，明确写该证据层级，不据此宣称新 BIT 已经硬件通过。

本轮整理版的独立实测更新见[current_validation.md](../reference/current_validation.md)；本页历史表保留原身份。
