# 历史阶段、证据索引与可引用结论

本页按历史阶段组织原始参考，保留各版本的现象、处理与数据身份；当前发布验证另见[当前验证](current_validation.md)。所有文件的精确路径、阶段、大小和SHA256见[anomaly_sources.json](../../evidence/anomaly_sources.json)。异常逐项解释见[anomaly_register.md](anomaly_register.md)。

## 阶段不能混用

| 阶段 | 已有证据 | 可用结论 | 不能由此推出 |
|---|---|---|---|
| 旧QVGA/低速VGA | h01转述早期日志、50张验收 | 当时配置/预取/同步修正与限定验收 | 新高速连续版永久无错；早期原始记录本次已逐条重验 |
| 高速视频诊断 | h02至h10 | 旧FIFO区间、采样后移改善、相邻字节角色互换及2500帧具体失败 | 线长或RCK唯一根因；色条错误率等于实景错误率 |
| 旧视频收敛 | h01 | 第324帧内容错误、USB断连和后续补测分别保留 | 后测通过抹除失败；该版Flash等于OCR Flash |
| PC调度固定ROI分割 | o05 | 新100帧DDN7870及1010字符数值链的旧阶段结果 | 完全自主识别；该文档位于自主目录就属于自主构建 |
| build_current_roi | o04 | 当前标定位置100帧BD12345；5.62694次/s七字符OCR | 任意位置定位；旧1至2字符7.50258次/s等于七字符速度 |
| build_osd | o06 | 文字原子提交、完整LCD链仿真、历史用户确认文字可见 | 20帧移动场景识别通过；最终屏幕受原图CRC覆盖 |
| build_locator | o02/o13/o14 | 动态亮底ROI及其模型/RTL证据；完整入镜失败仍明确 | 0/10错误场景可用于准确率；定位成功等于整牌成功 |
| build_prefix | o03/o15 | 20/20排除AG伪前缀 | 中文识别已实现；BD12345完整成功，实际0/20 |
| build_split | o01/o07至o12/o16/t01/t02 | 4/5细桥拆分、100个连续完整组BD12345、冻结构建资源/时序 | 任意车牌100%；本轮工程整理版已经通过相同板测 |
| 工程整理原计划 | p01/p02 | 记录当时结构与验证要求；后续实施见当前验证 | 计划勾选替代实际执行证据 |

## 历史继承基线的精确账本

build_split产物汇总o11记录BIT SHA256为`81e421b371d8b4d5b3e77757b87d8c9e67e1c3ab74dcd395e331a02284dd1297`，LTX为`5843c174a9bedfaa714babdc12e381b0b198eb46743295feaf486b77c2eeeeb3`，模型为`179d6d9b9a4e2229c152770152fe6c8d71ff924af5d9da06132debd730cf4645`。这里是读取已有清单的身份记录，文档整理没有再次下载该BIT。

| 字段 | 证据值 | 来源及口径 |
|---|---:|---|
| 完整识别组/正确号码 | 100/100，BD12345 | o07；同一号码、当前完整入镜场景 |
| 接纳源帧号 | 5249至5645，步长4 | o07逐路径帧号；表示每4个源帧接纳一次OCR |
| 字符、归一化像素、CNN分数 | 700；537600；25200 | o08；均与整数参考一致，不等同泛化准确率 |
| 相机源开始节拍 | 22.507769042448196 fps | o08，100MHz FPGA时间戳 |
| 识别结果完成节拍 | 5.626956163353177次/s | o08，与相机速率分列 |
| 采集至识别结果 | 平均161.7688653ms | o08；不含未来新版本推断 |
| 会话完整性 | 1开头残组；0CRC候选拒绝；末尾1200字节半包 | o07；不把会话边界写成零截断 |
| 板上错误/发布丢弃 | 均0 | o08；不自动证明所有PC/USB事件不存在 |
| 主动跳过源帧 | 增量297 | o08；不能写成视频丢帧 |
| 拆分对照 | 88张新增1框、12张原7框保持 | o16；同原图/ROI比较 |
| 初次/最终WNS | −0.330ns / +0.088ns | t01/t02；初始失败保留 |
| 最终WHS | +0.006ns | t02，setup/hold失败端点0 |
| 资源 | LUT15587，FF18829，40RAMB36+9RAMB18，DSP9 | o11；BRAM36等效44.5/50=89% |

旧首轮split_aligned_100也得到100个正确完整组，但有内部4个不完整组、1开头残组和1次CRC候选拒绝（o09），不能同复测合并称200帧无断片。此前split_board_100为零字符100组（o12），是截边场景下的空定位参考通过，不是识别成功。

## 统计单位与复用限制

854张保存图回放（o10）中30张受细桥修复，824张原框/结果不变且保留1张B/H错误；重复同场景帧具有相关性。15组合成平移（o02）只证明那张实拍图在指定合成变换的结果，不能表述为15个实拍位置。通用字体测试m01整数准确率81.25%、2880字符样本，浮点/整数预测一致率约99.1319%；这两个数和整牌100/100是不同分母、不同任务。训练阶段按验证集选epoch20，m01明确未以真实相机评估选择训练；训练/验证样本独立性需结合数据清单单独核查，不从该摘要推导。

固定色条2500帧仅1帧错误（h08/h09）对应该轮0.04%；600双通道UART包CRC正确（h10）只证明传输一致，字段reference_checked=false，不能因为reference_bad_frames=0而说600帧场景正确。照明暗纹是历史用户观察；斜刷新、电气边沿、器件健康均未受控闭环。h01中私人会话行号和早期链接只是其历史来源，本次未重新打开整份会话，不声称已核对每条原话。

## 历史记录的取材范围

1. 没有外部WCK/PCLK和模块端RCK/电源波形，不能把内部发沿计数替代实物收到的沿；缩短所有相机线的相关改善不是RCK单线因果证明。
2. 没有AEC/AGC独立开关受控对照、反接后器件健康测量、受控无频闪光源及LCD光学刷新测量。
3. 旧EDGE失败未保存坏CRC的记录不能补造；旧视频第324帧事件本次主要引用综合台账，未重新分析原始fault.json。
4. 本次读到了汇总、诊断和时序报告，未重跑全部wire.bin或重验全部图片；需复现实验时按本索引回到对应阶段原目录，保存新的结果且不覆盖旧记录。
5. 当前同场景100组通过不覆盖任意号码、中文识别、强透视/运动、厚桥或三字粘连；B/H已有保留反例。后续准确率应由预先定义且独立的数据集给出。
6. 本轮整理版验证必须由它自己的冻结源、构建、日志和实机结果提供；此文件不将build_split历史数值改名为新工程结果。

## 实际读取文件

下面每个编号对应清单同名id。链接指向随包保存的历史副本；移动或分发文档时以文件SHA256确认副本身份。哈希确认文件内容身份，不能单独证明其中叙述为真或测试已在本轮重做。

### h01

- 阶段：历史视频与工程收敛。
- 类型：历史综合台账；引用会话未在本次逐条重开。
- 文件：[historical/release_lcd_v04/stream_video_edge_20fps/docs/anomaly_register.md](../../evidence/history/release_lcd_v04/stream_video_edge_20fps/docs/anomaly_register.md)。
- SHA256：`ed0a947311f8184fdfd04678f067dca79d386e995448bf08df7fa23e48d3332a`。

### h02

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史说明。
- 文件：[historical/video20fps_20261030/docs/dynamic_image_fault_20261031.md](../../evidence/history/video20fps_20261030/docs/dynamic_image_fault_20261031.md)。
- SHA256：`b1fad4e5d83f20c0d61a8ab61835f433242cf3f82b3cdfc6e41d122ae597750f`。

### h03

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史说明。
- 文件：[historical/video20fps_20261030/docs/byte_phase_evidence_20261031.md](../../evidence/history/video20fps_20261030/docs/byte_phase_evidence_20261031.md)。
- SHA256：`c5e77aa253a8f7e968a051674220bfae3033c6daadb53d08a234347ed306c6f2`。

### h04

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史说明。
- 文件：[historical/video20fps_20261030/docs/diagnostic_findings.md](../../evidence/history/video20fps_20261030/docs/diagnostic_findings.md)。
- SHA256：`e37f8805a0aba1a73ccf2a54d60399e4810f4aa4babc617d3ae1782f44f40dcb`。

### h05

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史说明。
- 文件：[historical/video20fps_20261030/docs/sample40_experiment.md](../../evidence/history/video20fps_20261030/docs/sample40_experiment.md)。
- SHA256：`9cd0411726e95369678a4858653a3cb5325d0c97b1f04834af5809685e00ae8f`。

### h06

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史说明。
- 文件：[historical/video20fps_20261030/docs/short_adapter_wiring.md](../../evidence/history/video20fps_20261030/docs/short_adapter_wiring.md)。
- SHA256：`b9620bb9b9bc1be9ca6a1fd2c2cc34a9be9ced0a838a09dca6315abad2ddd01a`。

### h07

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史说明。
- 文件：[historical/video20fps_20261030/docs/statistics2500_result.md](../../evidence/history/video20fps_20261030/docs/statistics2500_result.md)。
- SHA256：`b7ef9fd285f3cc609b9edac1ecf0d0e19a94b2ce1a837179eb7ee7136f353557`。

### h08

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史机器结果。
- 文件：[historical/video20fps_20261030/reports/lcd/runtime/stats2500_run01/summary.json](../../evidence/history/video20fps_20261030/reports/lcd/runtime/stats2500_run01/summary.json)。
- SHA256：`2a439135364bc7b2f57c25d5d45314a1046c9009ec5bb6d93f4c18c23fa65ec6`。

### h09

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史机器结果。
- 文件：[historical/video20fps_20261030/reports/lcd/runtime/stats2500_run01/bad_frame_analysis.json](../../evidence/history/video20fps_20261030/reports/lcd/runtime/stats2500_run01/bad_frame_analysis.json)。
- SHA256：`142d5dfd8ed6d7dc94c299705c0b498ae96afa6f5193951eb86713e16e9cfc91`。

### h10

- 阶段：高速视频诊断，2026-10-30至10-31。
- 类型：历史机器结果。
- 文件：[historical/video20fps_20261030/reports/uart_pairs/pair_uart_scene_01/summary.json](../../evidence/history/video20fps_20261030/reports/uart_pairs/pair_uart_scene_01/summary.json)。
- SHA256：`1064f6d879393d1931bc58547bbb000f475d7eb994580b1ff51bc6a9fc4b9c97`。

### o01

- 阶段：build_split。
- 类型：历史说明。
- 文件：[historical/plate_autonomous_board_20261101/docs/touching_character_split.md](../../evidence/history/plate_autonomous_board_20261101/docs/touching_character_split.md)。
- SHA256：`23f86e05d28f913407248b4515e3887dda096f590bd23cd26d136cb8110f6f24`。

### o02

- 阶段：build_locator。
- 类型：历史说明。
- 文件：[historical/plate_autonomous_board_20261101/docs/placement_tolerance_report.md](../../evidence/history/plate_autonomous_board_20261101/docs/placement_tolerance_report.md)。
- SHA256：`b7a431336baa49e52eab814d6a1f04ada73d0015629a663c4349028637b5e3fd`。

### o03

- 阶段：build_prefix。
- 类型：历史说明。
- 文件：[historical/plate_autonomous_board_20261101/docs/chinese_prefix_filter.md](../../evidence/history/plate_autonomous_board_20261101/docs/chinese_prefix_filter.md)。
- SHA256：`61c340073f2bd2083290b4a9876bce703f2b0a2958ad49f194c9d0ad5252f61a`。

### o04

- 阶段：build_current_roi及此前。
- 类型：历史说明。
- 文件：[historical/plate_autonomous_board_20261101/docs/autonomous_board_test_report.md](../../evidence/history/plate_autonomous_board_20261101/docs/autonomous_board_test_report.md)。
- SHA256：`820b44a89fc5049a318b6ad7cd71e3c9ebe624e50194b605899929e622579c97`。

### o05

- 阶段：旧人工分割阶段；文档自身指向plate_segment_board_20261101。
- 类型：历史说明。
- 文件：[historical/plate_autonomous_board_20261101/docs/board_test_report.md](../../evidence/history/plate_autonomous_board_20261101/docs/board_test_report.md)。
- SHA256：`21163367c95d8180be41a58e8912d35ecee4d652dd2e47c912fa06f3da95b442`。

### o06

- 阶段：build_osd。
- 类型：历史说明。
- 文件：[historical/plate_autonomous_board_20261101/docs/lcd_result_overlay.md](../../evidence/history/plate_autonomous_board_20261101/docs/lcd_result_overlay.md)。
- SHA256：`2e4e040d95feba85b5a7f92fb38155cca167763ba21d7c6cacf4024a62dd5451`。

### o07

- 阶段：build_split，连续100完整组复测。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/split_aligned_repeat_100/summary.json](../../evidence/baseline/reports/split_aligned_repeat_100/summary.json)。
- SHA256：`4ed00ca4def77b195bb4a089a670d234376f5b665ab5c5821c0d786b59ad916d`。

### o08

- 阶段：build_split，连续100完整组复测。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/split_aligned_repeat_100/metrics.json](../../evidence/baseline/reports/split_aligned_repeat_100/metrics.json)。
- SHA256：`7b18f0845bc6261a769563cbcc5b162eddf185c6c242d08eabb6f80853bd12d3`。

### o09

- 阶段：build_split，首轮有内部断片。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/split_aligned_100/summary.json](../../evidence/baseline/reports/split_aligned_100/summary.json)。
- SHA256：`804df3c9a8e9649957067dfb2c2c16f7ad69a7530e2761664d4729df2775fc1b`。

### o10

- 阶段：build_split，854张保存图回放。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/split_reference/summary.json](../../evidence/baseline/reports/split_reference/summary.json)。
- SHA256：`205968de2ca385e6afa6307d98367cdcb9bd546511efc2139e84be816d627ca0`。

### o11

- 阶段：build_split，产物汇总。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/split_artifacts.json](../../evidence/baseline/reports/split_artifacts.json)。
- SHA256：`2afbe8275adbce6e227fe2924a9b7bda050f9e0c0c6d23e145cf3d5c4a6c465a`。

### o12

- 阶段：build_split，牌面截边空定位。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/split_board_100/summary.json](../../evidence/baseline/reports/split_board_100/summary.json)。
- SHA256：`f2fc9f3347baa17ef5d40c21a2ba356cf12b29f44b88e43115cf450ea88692da`。

### o13

- 阶段：build_locator，换场景预检。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/locator_board_precheck/context.json](../../evidence/baseline/reports/locator_board_precheck/context.json)。
- SHA256：`13f2b798a0546576dd3c40ce5daffa2683c88e7ca817745128e6ccd40b11a3a3`。

### o14

- 阶段：build_locator，完整入镜失败。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/placement_test_03/diagnosis.json](../../evidence/baseline/reports/placement_test_03/diagnosis.json)。
- SHA256：`5177f754bbb9546d776bcf2866b63628420c02c1acd1fa671cba44ed0c1fa266`。

### o15

- 阶段：build_prefix，20组。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/prefix_board_20/summary.json](../../evidence/baseline/reports/prefix_board_20/summary.json)。
- SHA256：`a487b40a4386ceca43bffed0d3cb19cef88761a816c3b8a1614c88831e52c19c`。

### o16

- 阶段：build_split，拆分对照。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/reports/split_aligned_repeat_100/split_box_check.json](../../evidence/baseline/reports/split_aligned_repeat_100/split_box_check.json)。
- SHA256：`0c42f3a2fbda0d2d210bbcddd4922f647d79a8bf2e2afdcc78dc0831bf75a511`。

### t01

- 阶段：build_split，初次布线失败。
- 类型：历史工具报告。
- 文件：[historical/plate_autonomous_board_20261101/build_split/timing.rpt](../../evidence/history/plate_autonomous_board_20261101/build_split/timing.rpt)。
- SHA256：`03786e06800f415844511dd418b7fa9339b8a6330e033d67d7c5c073c3056e60`。

### t02

- 阶段：build_split，物理优化后。
- 类型：历史工具报告。
- 文件：[historical/plate_autonomous_board_20261101/build_split/timing_refined.rpt](../../evidence/history/plate_autonomous_board_20261101/build_split/timing_refined.rpt)。
- SHA256：`bc739e8db3d0b39c8fb0cab28ad009131109a7f31abf7ec1b1a5c85e6467deea`。

### t03

- 阶段：自主遥测初版，失败。
- 类型：历史工具报告。
- 文件：[historical/plate_autonomous_board_20261101/build_final/timing.rpt](../../evidence/history/plate_autonomous_board_20261101/build_final/timing.rpt)。
- SHA256：`05ebc15e88d12fcf4f2bf521d04a85e2bc385935866deeeddfce09fdfc163fb9`。

### m01

- 阶段：冻结模型训练及离线评估。
- 类型：历史机器结果。
- 文件：[historical/plate_autonomous_board_20261101/model/training_result.json](../../project/model/training_result.json)。
- SHA256：`ff1060dee32878371d4a94e4eb9b83e9d9713aa0c665cf5f571da40f5ea3f0d0`。

### p01

- 阶段：本轮工程整理。
- 类型：任务约束；不是板测证据。
- 文件：[project/docs/engineering_spec.md](../archive/engineering_spec.md)。
- SHA256：`fd6119982ea9b19f9c1169577ae35535bcc54a3167496577136f762d847a1efe`。

### p02

- 阶段：本轮工程整理。
- 类型：任务约束；不是板测证据。
- 文件：[project/docs/engineering_plan.md](../archive/engineering_plan.md)。
- SHA256：`cf467202b7ec9853fdca6f9ac9cec29d480f0ec4ef4800c6c2a11394a6dee8e0`。
