# 识别结果与验证数据

## v1.1 蓝底白字同图验证

五帧实拍输入位于[blue_before](../../evidence/blue_polarity/blue_before/summary.json)，原板端依次输出 `1AW`、`1AW`、`01`、`0D`、`01`。在同一原图上保留原定位，分割和归一化改用flags=2，冻结模型五帧均输出 `AL67L8`，每帧六个字符；见[逐帧离线结果](../../evidence/blue_polarity/blue_seg_invert_probe.json)。这些是软件重推理结果，不能计为新BIT的板端一致性或实机正确率。

原图人工目视可读为“晋A·L67L8”，因此英数字预期读数为 `AL67L8`；用户当时确认已对准，但未单独提供号码真值，原采集未填truth评分字段。应将五帧输出和目视读数分别保存。原板端五组与旧参考全部一致，说明本次修复针对字符极性语义。定位/极性对照和适用条件见[白字支持](white_character_support.md)，新板测结果见[当前验证](current_validation.md)。

## v1.1 新程序板测

新BIT在当前蓝牌上完成20组自主识别，20组全部输出AL67L8，与人工目视读数匹配；120字符、92,160个归一化像素及4,320个分数全部与整数参考一致。[原始summary](../../evidence/blue_polarity/board_white_20/summary.json)、[metrics](../../evidence/blue_polarity/board_white_20/metrics.json)、[评分来源](../../evidence/blue_polarity/scoring_context.json)。该结果为同一静态场景的重复结果；未新增跨位置、多牌号准确率主张。

## v1.0与历史结果总表

本页把硬件实现一致性和真实文字评分分别列示。以下engineering_03为v1.0绿色ROI基线；engineering_02为不带框三模式版；build_split为历史算法基线。

| 版本与场景 | 完整组 / 参考一致 | 字符数 | 整串真值匹配 | 实际输出 |
|---|---:|---:|---:|---|
| v1.0 engineering_03，K38817 | 10 / 10 | 70 | 0 / 10 | `1K38817` 2次，`GK38817` 8次 |
| engineering_02，K38817 | 100 / 100 | 800 | 0 / 100 | `WGK38817` 65次，`MGK38817` 35次 |
| 历史build_split，对齐BD12345 | 100 / 100 | 700 | 100 / 100 | `BD12345` 100次 |

原始证据：[当前10组](../../evidence/validation/roi_board_10/summary.json)、[当前metrics](../../evidence/validation/roi_board_10/metrics.json)、[前版100组](../../evidence/validation/engineering_board_100/summary.json)、[历史100组](../../evidence/baseline/reports/split_aligned_repeat_100/summary.json)。当前10组的53760个归一化像素、2520个CNN分数均与整数参考一致；前版100组的614400个像素、28800个分数均一致。

当前K38817场景的多余前导字符来自候选区域：前版首帧ROI为`[12,29,151,80)`，左1/8排除线x=29，两个多余候选中心为33与30.5，均被位置规则保留。具体框见[失败区域图](../../evidence/validation/engineering_board_100/segmentation_failure.png)和[诊断](../../evidence/validation/engineering_board_100/scene_failure_analysis.json)。该规则没有汉字分类能力。当前框版本仍有一个多余前导字符；摆放、光照和采样未受控，不能把两版候选数量差异归因于算法改善。用户接受的是当前显示效果，前缀与摆放适用性继续按独立场景评估。

历史BD12345的100/100属于同牌面、对齐摆放条件的重复结果；它证明该条件下的完整链路与识别表现。当前统计支持精确的数值实现结论与场景结果，不据此外推任意牌号准确率。36类模型面向英数字，中文省份字不在分类输出中。

## 历史数据口径

以下保留各阶段原始数据、分母和处理版本。原件位于`evidence/baseline/reports/`，来源身份见[data_sources.json](../../evidence/data_sources.json)。

BASELINE指历史build_split，以下数字按各阶段落盘JSON及逐帧记录保留；v1.0基线结果已列于上表。

## 计数与评分定义

- `captured_complete_frames`：观察器组装完整的数据组数。自主协议中，同一 epoch/frame_id 的原图、分割、字符信息、结果共同构成一个待验证组；字符数为零仍可形成完整组。
- `verified_frames` / `mismatched_frames`：完整组内硬件与对应协议版本整数参考的校验结果。比较包含 ROI、分割框、归一化像素、CNN 有符号分数与输出类等。`passed=true` 不是车牌真值正确的同义词。
- `verified_characters`：实际经过字符比较的数量；像素比较分母 `N_char × 32 × 24`，分数比较分母 `N_char × 36`。同一 argmax 不等于 36 个分数逐项相等。
- 字符分类正确率：带标签字符样本中 `argmax(score)==label` 的数量除以样本总数。训练 JSON 中的这一数字与硬件/软件一致率不同。
- 整串精确匹配率：有指定真值的完整结果中，输出字符串完全等于 `truth_for_scoring_only` 的帧数除以相应完整帧数；没有真值时不计算。不完整组不进入此分母，必须另外报告其数量。
- “连续 100 个识别结果”指调度接受并完成的识别序列连续；视频源帧号不必相邻。忙时跳过源帧、串口缺失结果以及识别错误属于不同维度。
- `truth_for_scoring_only` 是评分字段；现有脚本在预测完成后与字符串比较。它不能作为模型输入、分割搜索答案或排除困难帧的依据。

## 历史实机及回放结果

以下逐行连接原始 summary，`等价` 只表示完整组参考一致，`真值` 为原采集对应硬件版本的整串匹配。所有表项均为历史。

| 阶段/数据 | 完整/等价组 | 比较字符 | 真值精确匹配 | 不完整组 | 解释 |
|---|---:|---:|---:|---:|---|
| [current_roi_auto_100](../../evidence/baseline/reports/current_roi_auto_100/summary.json) | 100/100 | 700 | 100 | 1 | 固定 ROI 自主基线，同一 BD12345 场景 |
| [locator_board_precheck](../../evidence/baseline/reports/locator_board_precheck/summary.json) | 10/10 | 0 | 0 | 1 | 动态定位板测；无字符结果，不能算识别成功 |
| [placement_test_03](../../evidence/baseline/reports/placement_test_03/summary.json) | 10/10 | 80 | 0 | 1 | 动态定位阶段仍有多余前缀及粘连问题 |
| [prefix_board_20](../../evidence/baseline/reports/prefix_board_20/summary.json) | 20/20 | 120 | 0 | 0 | 前缀排除成功；尾部粘连仍输出 BD123M/BD123K |
| [split_board_100](../../evidence/baseline/reports/split_board_100/summary.json) | 100/100 | 0 | 0 | 1 | 目标未有效进入识别区域；100 组零字符，不是 100 帧正确 |
| [split_aligned_precheck](../../evidence/baseline/reports/split_aligned_precheck/summary.json) | 10/10 | 70 | 10 | 1 | 对齐后预检 |
| [split_aligned_100](../../evidence/baseline/reports/split_aligned_100/summary.json) | 100/100 | 700 | 100 | 5 | 完整组均正确，但传输有间断，不能称连续 100 结果 |
| [split_aligned_repeat_100](../../evidence/baseline/reports/split_aligned_repeat_100/summary.json) | 100/100 | 700 | 100 | 1 | 同一场景连续 100 个识别结果，保留开头残缺组 |
| [split_chain_replay](../../evidence/baseline/reports/split_chain_replay/summary.json) | 2/2 | 7 | 未评分 | 0 | 仿真 wire 回放；非实机新采集 |
| [split_legacy_replay](../../evidence/baseline/reports/split_legacy_replay/summary.json) | 20/20 | 120 | 未评分 | 0 | 历史 prefix wire 按旧协议语义回放；非新算法重推理 |

前缀阶段的 [prefix_artifacts.json](../../evidence/baseline/reports/prefix_artifacts.json) 显示：20 帧每帧排除 2 个前缀候选，保留框不变，硬件与参考一致；输出 BD123M 13 帧、BD123K 7 帧，整串真值仍是 0/20。它证明前缀处理行为，不能宣称整串识别通过。

### 有间断采集与重复采集

| 项目 | split_aligned_100 | split_aligned_repeat_100 |
|---|---:|---:|
| 完整组 / 真值正确 | 100 / 100 | 100 / 100 |
| 不完整组 | 5 | 1 |
| parser rejected_candidates | 1 | 0 |
| discarded_bytes / truncated_bytes | 37988 / 1200 | 6058 / 1200 |
| 源帧号首末 | 2973 → 3441 | 5249 → 5645 |
| observed_source_frame_gaps | 368 | 297 |
| FPGA skipped_frames 首末 | 1657 → 2008 | 3364 → 3661 |
| publisher_dropped 首末 | 0 → 0 | 0 → 0 |
| capture_seconds | 21.21931110 | 18.05562860 |
| 观测识别结果率，FPGA 时间戳 | 4.76125910 fps | 5.62695616 fps |

首轮 468 个源帧间隔中，硬件 skip 增量 351，推得 117 个接受间隔；只观测到 99 个完整结果间隔，所以不能用 100 个正确完整组覆盖缺失。现有证据定位到记录/传输不完整，尚不能仅靠摘要把根因唯一归于 PC、驱动或电气链路。

重复轮首末差 396，99 个间隔均为 4；`396 - (3661-3364)=99`，与完整结果间隔数一致。其唯一 rejected group 是 frame_id=5245、缺少 AIF1、已有字符索引 0..6，早于首完整帧 5249；`reason=capture_ended` 是观察器结束时清理残组的标签，不代表它是末尾新失败帧。连接正在发送的数据流可形成开头残包，不能把该组删掉以声称“零残缺”。尾部 `truncated_bytes=1200` 仍如实保留。

重复轮有 700 个字符，537600 个归一化像素、25200 个整数分数，均零差异；100 个字符串均为 BD12345。这是固定场景重复稳定性与整数实现一致性证据，不是 100 个独立车牌样本或泛化正确率。

## 离线同图新旧分割比较

依据 [split_reference/summary.json](../../evidence/baseline/reports/split_reference/summary.json) 以及 [逐帧输入与预测](../../evidence/baseline/reports/split_reference/frames.json)。两个分支使用同一原图、同一 ROI/方向/极性、同一冻结模型；区别是是否启用 touching split。这是软件重推理，因此结果可能不同于原采集 summary 中旧硬件的输出。

| 保存场景 | 帧数 | 旧分割整串正确 | 新分割整串正确 | 框改变帧 | 新退化帧 |
|---|---:|---:|---:|---:|---:|
| current_roi_auto_100 | 100 | 100 | 100 | 0 | 0 |
| current_roi_precheck | 4 | 4 | 4 | 0 | 0 |
| osd_board_20 | 20 | 19 | 19 | 0 | 0 |
| placement_test_03 | 10 | 0 | 10 | 10 | 0 |
| prefix_board_20 | 20 | 0 | 20 | 20 | 0 |
| anp639 | 200 | 200 | 200 | 0 | 0 |
| d12345 | 100 | 100 | 100 | 0 | 0 |
| k38817_old | 200 | 200 | 200 | 0 | 0 |
| k38817_v2 | 100 | 100 | 100 | 0 | 0 |
| ddn7870 | 100 | 100 | 100 | 0 | 0 |

合计 854 帧：旧分割 823/854，新分割 853/854，新增正确 30 帧，新退化 0 帧；仍有 1 帧 HD12345。后五组为保存的其他场景，并非 700 个不同车牌。前五组使用图像定位 ROI，后五组依据 `norm_ref.SCENES` 中既有 ROI/旋转/反相配置，不能称为 854 帧统一自主定位实机测试。阶段性设计曾查看这些场景，结果不构成独立测试集泛化估计。

[locator_reference](../../evidence/baseline/reports/locator_reference/summary.json) 另记 124 帧离线定位回放，123 帧 BD12345、1 帧 HD12345，并明确四张 probe 图参与几何设计；不能将这 124 帧与后续重复使用的帧相加当作新样本。`current_roi_precheck` 原采集真值 0/4，但同图离线新前端是 4/4；`osd_board_20` 原采集真值 0/20，同图离线是 19/20。这些数字属于不同处理版本，应同时注明阶段。

## 复核边界及后续所需材料

当前保存记录没有独立车牌身份划分、多地点多光照覆盖、随机抽样方案、独立标注复核表或完整公开真实车牌测试集。因此不能由上述帧率和正确帧数推导任意车牌识别率。中文省份字符不在 36 类模型输出中；评估目标应写英数字串，不宣称完整中文车牌 OCR。重复场景不足以计算独立同分布样本的置信区间。

后续新增评估继续保存版本哈希、实际场景、真实文本、原始图像、分数及统一计时字段。

当前发布完整验证链见[当前验证](current_validation.md)。
