# 相机自主字符识别测试报告

本报告记录 `build_current_roi` 阶段的识别验收。后续 `build_osd` 角落显示功能及新增实机证据见[叠字说明](lcd_result_overlay.md)；下文未叠加文字的描述属于原阶段。

## 当前部署版本验收结果

- [x] 当前ROI构建完成并下载配置RAM：WNS +0.148 ns、WHS +0.012 ns；14,460 LUT、18,198 FF、40 RAMB36+9 RAMB18、9 DSP；DRC 41项普通Warning，0 Error/Critical。程序哈希见[最终文件清单](../reports/final_artifacts.json)。
- [x] 当前 ROI 版本完成 **100 帧新实拍 AUTO 被动核验**：100/100 输出 BD12345；700 字符的 537,600 个归一化像素、25,200 个 CNN 分数全部与整数参考一致，字符框和硬件 ASCII 一致。
- [x] 七字符识别完成速率 5.62694 次/s，源帧 start 速率 22.50775 帧/s；从接纳源帧到结果平均 148.526 ms。bad_captures=0、publisher_dropped=0，无 CRC 拒绝包。接收停止时留下的 1 组不完整数据不纳入验收。识别忙期间主动跳过 297 个源帧，是既定调度行为，不是视频丢帧计数。
- [x] 当前 BIT 切换 EDGE 后另验 4 帧、恢复实体开关后另验 4 帧：均完整识别 BD12345，中间计算全部匹配。当前已解除 VIO 开关覆盖，板上继续运行本测试程序；Flash 未更新。

证据：[100帧原始汇总](../reports/current_roi_auto_100/summary.json)、[100帧数值统计](../reports/current_roi_auto_100/metrics.json)、[EDGE检查](../reports/current_roi_edge_4/summary.json)、[实体开关检查](../reports/current_roi_physical_4/summary.json)。这些是同一固定场景的连续帧，不代表跨车牌、跨位置的总体识别准确率。

## 功能与测试范围

AUTO 模式由相机源帧触发：FPGA 检查完整 640×480 光栅，抽取 160×120 灰度图，冻结已有图像 RAM，顺序执行分割、32×24 灰度归一化、整数 CNN 和硬件有符号 argmax。识别忙时跳过后续源帧，视频继续运行。PC 仅通过 COM10、12 Mbps 接收观测包，不上传图像、字符框或启动命令；接收完毕后才运行参考算法核验。[设计合同](autonomous_plan.md)、[观察器](../pc/observe_auto.py)

模式保持为：SW13=0、SW12=0 时 AUTO；SW13=1 时人工上传；SW13=0、SW12=1 时相邻字节诊断。SW2 控制 LCD 的 RAW/EDGE 图像；当前 LCD 显示视频，尚未实现识别文字叠加。

当前对象为用户确认的 **BD12345，共七字符**。本实现使用按固定摆放场景标定的 ROI，不包含整幅图自动定位车牌，也未验证移动、任意位置或其他场景的识别鲁棒性。真值只用于预测后的评分。

## ROI 标定与逐层证据

| 条件与证据层级 | 已验证结果 | 证据 |
| --- | --- | --- |
| 旧 ROI `(26,35,158,87)`，100 帧实拍 AUTO | 100 帧均与整数参考逐项一致；共 195 字符、149,760 个归一化像素、7,020 个有符号分数，差异均为 0。但预测为 95 帧 `BD`、5 帧 `B`，未识别完整七字符 | [汇总](../reports/board_camera_100/summary.json)、[逐项统计](../reports/board_camera_100/metrics.json) |
| 当前 ROI `(26,41,150,76)`，100 帧已保存图像的软件回放 | 100 帧均输出 `BD12345`。ROI 按第一幅图像的几何区域选取，其余 99 帧用于回放检查 | [回放记录](../reports/current_roi_replay.json) |
| 当前 ROI，10 幅新采集图像经人工协议上板 | 10 帧均输出 `BD12345`；70 字符、53,760 像素和 2,520 分数全部一致。此项由 PC 上传原图并调度硬件，不属于 AUTO 被动实拍验收 | [人工上板记录](../reports/board_manual_current_roi/summary.json) |
| 当前 ROI，自主完整链 RTL 仿真 | 相机接口输入完整光栅，UART RX 恒为高；七字符帧与空帧均通过。UART 引脚采样的 13 包、45,824 字节通过 CRC、原图、框、5,376 像素、252 分数和 ASCII 核验 | [仿真日志](../logs/auto_current_scene_simulate.log)、[串口核验](../sim_work/auto_current_scene/wire_verification.json) |
| 当前 ROI，新 BIT 的100帧实拍 AUTO | 100/100 完整识别 BD12345；700 字符、537,600 像素、25,200 分数均一致；PC 仅接收 | [最终验收](../reports/current_roi_auto_100/summary.json) |

旧 ROI 中，数字区域与牌外背景在二值图上连成宽连通域，未通过字符候选筛选，因此硬件与参考都只输出前面的字母。当前 ROI 排除该背景连通区域；字符数量仍由原分割算法决定，没有硬编码为七个。[连通域诊断](../reports/board_camera_precheck/segmentation_diagnosis.json)、[二值图](../reports/current_binary_mask.png)

旧 ROI 的 `bad_captures`、`publisher_dropped` 均为 0。采集边界另有 1 组不完整数据，观察器已排除，没有计入上述 100 帧通过结果。这里的“逐项一致”表示硬件实现符合参考算法，不等于识别文本正确。

## 独立代码复核与保留功能

相对 `build_verified` 的冻结清单，本次源文件差异仅为 `plate_auto_controller.sv`、`plate_recognition_subsystem.sv` 和 `lcd_top.sv` 的 ROI 参数化及对应注释。控制器和子系统默认值仍为旧 ROI；顶层显式传入当前 ROI，分割、归一化与 AIF1 观测包使用同一组参数。人工模式仍使用上传协议给出的 ROI。已核对参数合法且右下端点不包含；未发现本次参数传递的具体缺陷。[冻结清单](../build_verified/sources/manifest.json)、[控制器](../rtl/plate_auto_controller.sv)、[子系统](../rtl/plate_recognition_subsystem.sv)、[顶层](../video_rtl/lcd_top.sv)

分割器、归一化器、CNN、模型、相机配置及采集、LCD 和 EDGE 工作单元与上述冻结清单的 SHA256 一致。模型 SHA256 为 `179d6d9b9a4e2229c152770152fe6c8d71ff924af5d9da06132debd730cf4645`。

既有回归已验证 AUTO→MANUAL 中途采集中止、MANUAL→DIAG 中途上传失效，以及 DIAG→MANUAL 新上传恢复；真实人工链两幅图的框、1,536 像素和 72 分数一致。相邻字节诊断实拍接收 10 帧，无 CRC 错误或硬件丢包。旧 ROI 下 RAW/EDGE 切换及重新打开观察器也分别获得 10 帧完整参考核验结果。[模式回归](../logs/auto_manual_final_simulate.log)、[诊断实拍](../reports/uart_pairs/auto_pair_regression/summary.json)、[EDGE](../reports/board_edge_10/summary.json)、[重新接收](../reports/board_camera_resume/summary.json)

## 帧率与时序证据

相邻字节诊断记录的源帧率为 **22.50774 帧/s**；旧 ROI 的 AUTO 记录由 100 MHz 时间戳得到源 start 帧率 **22.50775 帧/s**、识别完成帧率 **7.50258 帧/s**。后者每帧仅识别 1～2 个字符，不能用作当前七字符识别速度。源 start 帧率也不是对 LCD 光学刷新率的独立测量。[诊断统计](../reports/uart_pairs/auto_pair_regression/summary.json)、[AUTO 统计](../reports/board_camera_100/metrics.json)

初次 `build_final` 的 WNS 为 −0.474 ns，58 个负裕量端点均在新增遥测模块。为此在宽字节选择与 CRC/FIFO 写入之间增加寄存级；独立串口回归核验 26,388 个引脚采样字节、18 个合法包及 6 次预期丢包恢复。`build_verified` 经物理优化后达到 **WNS +0.170 ns、WHS +0.016 ns**。这些数值属于旧 ROI 构建，不能填作当前 ROI 的最终时序结果。[失败路径](../build_final/failing_paths.rpt)、[遥测回归](../reports/auto_uart_rtl/green.log)、[旧版优化后时序](../build_verified/timing_refined.rpt)

当前 `build.ps1` 在初次实现仅因时序检查失败、且已有布局布线检查点时执行优化；其他构建失败不会按时序问题继续。最终 `build_current_roi` 达到 WNS +0.148 ns、WHS +0.012 ns，TNS/THS 为 0；使用 14,460 LUT、18,198 FF、44.5/50 BRAM36 等效块、9 DSP。该资源数字包含保留的诊断功能，BRAM 已占 89%，后续扩展必须重新预算。[构建入口](../build.ps1)、[最终时序](../build_current_roi/timing.rpt)、[最终资源](../build_current_roi/utilization.rpt)

最终程序为 `build_current_roi/autonomous_board.bit`，SHA256：`d005c82731a1b2b4d060a915666d059829a469792130d75aaa73fbbae9e2c399`。本轮仅下载配置 RAM，断电后仍加载原 Flash 程序。

## 当前标定后的位移检查

新BIT预检4张均与参考一致，但图像向下移动了约9个小图像素，原固定ROI截断字符。用户确认生成/下载程序期间移动过相机或纸牌。将同一帧的ROI在软件中等量平移至(26,50,150,85)，又输出完整BD12345，说明该次错误来自固定区域与实物位置不一致，不能当作CNN计算故障。用户调回后，单张预检及随后100张自主验收均正确。固定ROI仍是当前应用限制，不能由这次通过推断已具备移动目标定位能力。[偏移预检](../reports/current_roi_precheck/summary.json)、[偏移图像](../reports/current_roi_precheck.png)、[调回预检](../reports/alignment_probe_01/summary.json)
