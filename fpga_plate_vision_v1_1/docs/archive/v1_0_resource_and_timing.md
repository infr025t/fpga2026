# 发布版资源、时序与吞吐

本页以 engineering_03 最终 refined 报告为准。目标器件为 `xc7a35tcpg236-1`，顶层 `lcd_top`，Vivado 2025.1；系统主时钟100 MHz。所有数据绑定[发布身份](../../evidence/validation/roi_tolerance_probe/implementation.json)及[冻结源清单](../../evidence/implementation/sources/manifest.json)。

## 实际资源

| 项目 | 当前 routed 用量 | 解释 |
|---|---:|---|
| Total LUT | 15,593 | Logic、LUTRAM、SRL合计 |
| Logic LUT | 14,066 | 逻辑用途 |
| LUTRAM | 1,492 | 分布式存储用途 |
| SRL | 35 | 移位寄存器用途 |
| FF | 18,895 | 寄存器 |
| RAMB36 | 40 | 36 Kb原语 |
| RAMB18 | 9 | 18 Kb原语 |
| BRAM36等效 | 44.5 / 50，89% | 40+9/2 |
| DSP | 9 | 整机DSP用量 |
| ROI 显示模块 | 64 LUT、62 FF | 0 BRAM、0 DSP |

原始报告：[utilization_refined.rpt](../../evidence/implementation/utilization_refined.rpt)。14066+1492+35=15593；层级资源包含其子级，父子实例不能相加。整机数字包含VIO、快照、协议等调试路径；ROI自身开销来自模块行，全工程前后差值还受布局与综合映射影响。

## 存储分配与系统组织

视频滤波采用行缓存：Gaussian三行8位灰度约1920字节，Sobel三行16位数据约3792字节。OCR保留一幅160×120小图，有效负载19200字节，按5个4096字节bank实现；采集、定位、分割及归一化依次持有其端口。显示短队列为64字节。

识别还需要分割mask、连通域洪泛队列、激活RAM与权重ROM。CNN激活A/B数组合计4096字节；权重ROM声明32768字节，实际权重28872字节；60个int32偏置为240字节。逻辑字节数描述算法存储，物理BRAM还受位宽、深度、端口和bank分配影响。完整存储清单见[架构](../reference/architecture.md)。

这种分配让视频局部运算随像素推进，小图识别复用存储和计算资源，同时保留可观测性。相机外部FIFO、LCD显示存储和板内诊断快照分别承担其接口任务。

## 时序收敛

| 阶段 | WNS ns | TNS ns | WHS ns | THS ns |
|---|---:|---:|---:|---:|
| engineering_03 初次布线 | −0.069 | −0.091 | 见初次报告 | 见初次报告 |
| engineering_03 物理优化后 | +0.029 | 0 | +0.050 | 0 |

[初次时序](../../evidence/implementation/timing.rpt)、[最终时序](../../evidence/implementation/timing_refined.rpt)、[优化日志](../../evidence/implementation/refine.log)共同保留收敛过程。初次关键路径位于人工串口CRC链；物理优化沿用既定流程，RTL和时序约束保持一致。WNS/WHS表示相应约束下的最差建立/保持裕量，不能换算成单帧识别延迟。

[check_timing](../../evidence/implementation/check_timing_refined.rpt)记录no_clock=0、unconstrained_internal_endpoints=0，同时列13个no_input_delay和8个partial_input_delay输入；[DRC](../../evidence/implementation/drc_refined.rpt)摘要为42项Warning。外部输入预算、路径例外与构建提示集中说明在[异常台账](../reference/anomaly_register.md)，原报告可逐对象核查。

## 视频与识别的速率

| 版本 / 场景 | 源帧起始 fps | OCR 结果 fps | 采集至结果平均 ms | 字符数 / 结果 |
|---|---:|---:|---:|---:|
| 当前 ROI 版，K38817 场景，10组 | 22.507753 | 5.626485 | 165.861397 | 7 |
| 三模式版，K38817 场景，100组 | 22.507754 | 4.501570 | 180.1293 | 8 |
| 历史 build_split，对齐 BD12345，100组 | 22.507769 | 5.626956 | 161.768865 | 7 |

证据：[当前metrics](../../evidence/validation/roi_board_10/metrics.json)、[三模式metrics](../../evidence/validation/engineering_board_100/metrics.json)、[历史metrics](../../evidence/baseline/reports/split_aligned_repeat_100/metrics.json)。表内字符数是实际候选输出数量；场景、摆放和候选工作量不同，三行用于说明系统调度范围，不能作为ROI框提高识别速度的受控对照。

当前10组的单字符归一化平均1.131466 ms、CNN固定9.42444 ms；分割记录平均47.54038 ms。识别控制器忙时保持当前小图所有权，并跳过新源帧；视频继续显示。当前相邻识别帧跨4个源帧，三模式8候选记录跨5个源帧，因而呈现约22.51 fps的视频源节拍和4.50–5.63 fps的识别结果节拍。

## 时间戳计算

计数来自100 MHz FPGA时钟。令相邻源帧号为F_i，采集起始tick为t_i，采集至结果周期为e_i，按同epoch且相邻间隔有效的结果计算：

- `Δt_i=(t_(i+1)-t_i) mod 2^32`。
- `f_input=ΣΔF_i × 100000000 / ΣΔt_i`。
- `f_capture=有效间隔数 × 100000000 / ΣΔt_i`。
- `Δr_i=(t_(i+1)+e_(i+1)-t_i-e_i) mod 2^32`，`f_result=有效间隔数 × 100000000 / ΣΔr_i`。
- `latency_ms=e_i/100000`。

32位tick约42.95秒回卷，保存记录的相邻间隔远小于该范围。100个结果用99个间隔计算；平均延迟的倒数不等于实际结果率，因为接纳还受视频帧起点约束。源起始率来自板端数字计数，LCD光学刷新是另一测量对象。12 Mbaud、8N1的UART理论有效字节率上限为1.2 MB/s，协议与传输间隔另占时间。

历史完整资源层次和首次收敛过程见[基线资源归档](../archive/baseline_resource_and_timing.md)。
