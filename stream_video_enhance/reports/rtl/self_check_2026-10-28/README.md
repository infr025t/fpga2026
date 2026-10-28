# 自查与错误恢复修复

日期：2026-10-28。检查基线：`3beefb2`。[工程入口](../../../README.md) · [当前规格](../../../docs/spec.md) · [验证清单](validation.json)

本轮自查运行时、8位屏幕链路和验证脚本，复现并修复三类问题。数值算法、模型/profile、NT35510 RTL、初始化寄存器表和旧Demo保持原字节；历史报告不改写。本轮行为证据来自Icarus及Python，Vivado失败路径使用受控子进程输出验证，没有执行真实Vivado或实板验收。

## 发现及修复

| 问题与触发方式 | 原行为 | 修复后行为 |
|---|---|---|
| 物理SOF进入入口RAM/预读后，核心接受SOF前收到源结束状态 | 失败原因可能丢失，错误帧被接受后误报超时；预缓存源提前给出的OK也可能丢失，使完整有效图像无法完成 | 待接收帧失败立即丢弃并保留原因；提前OK保存一项及frame_id，在接受同帧SOF时关联。覆盖WAIT_SOF和RECOVER中新SOF，重复OK或帧号不符按协议错误处理 |
| 屏幕profile寄存器表不变，但把接口宽度、字节顺序、方向或等待参数改错 | 已有寄存器对摘要等检查未约束这些接口元数据，仍可能报告PASS | 校验固定8位、MSB先发、RGB565、800×480横屏、初始化等待及已核验ZIP/C源码身份；不支持的配置或JSON类型明确拒绝 |
| Vivado编译/仿真失败结果没有simulation_summary字段 | 运行器读取该字段触发KeyError，汇总可能残留running | 摘要字段可缺省，正常返回失败码1，汇总记录failed及原始失败原因；超时和缺少PASS同样不能通过 |

入口修复见 [ingress_guard.sv](../../../rtl/ingress_guard.sv)。尚未接受的坏帧计入`dropped_source`，不增加`accepted_frames/invalid_frames`；已接受帧失败仍只增加一次`invalid_frames`。恢复后继续检查`accepted=completed+invalid`和`seen=accepted+dropped_source`，不通过篡改计数掩盖错误。

成功状态缓存只服务当前待接收帧，只有一项，不是任意多帧状态队列。RUN/DRAIN期间仍要求源结束状态属于当前活动帧；未来摄像头适配器须遵守既有单帧在途和S_FRAME包络，不可提前发送别帧状态。本轮没有改变FIFO容量，也未增加核心反压。

配置及脚本修复见 [生成检查](../../../scripts/generate_nt35510_rom.py)和[运行时测试入口](../../../scripts/run_runtime_tests.py)。屏幕物理数据口始终为`lcd_data[7:0]`；内部16位命令/参数和RGB565像素仍经两次8位写入。配置门禁增强没有改变实际初始化表。

## 验证与证据

| 范围 | 实际结果与归档 |
|---|---|
| 早到源状态专项 | 55/56拍各25个场景通过：18个接受前拒绝场景、5个提前OK完整帧场景，以及空闲孤立错误和接受后失败；各完成25帧。覆盖原因1…8、SOF至接受沿的4个相位、连续失败、恢复后首帧OK、重复/错误帧号和计数恒等式。正式结果见[运行时汇总](evidence/runtime/summary.json) |
| 修复前反例 | [原始失败状态丢失](evidence/early_status/red/simulate.log)把reason7误记为reason5；[只处理失败状态的中间版本](evidence/early_status/early_ok_red/simulate.log)仍丢失提前OK。中间版本源码及哈希保存在[冻结样本](evidence/early_status/negative_only_fixture/manifest.json)，不作为活动RTL编译 |
| 配置误通过反例 | [修复前](evidence/profile/results.json)的4个错误配置均返回PASS；[修复后](evidence/profile/results_green.json)全部返回失败码1。新增单元测试进一步覆盖16类字段篡改、来源身份及非法JSON类型 |
| Vivado失败路径 | [原KeyError记录](evidence/vivado_failure/reproduction.json)保留。回归覆盖编译、展开、仿真失败、超时和缺少PASS，均正常记录failed；这是模拟子进程输出的脚本契约测试，不计作真实Vivado通过 |
| 屏幕连续绘制 | [附加引脚模型](evidence/screen_additional/summary.json)实际通过：48×40面板/32×32有效区连续4帧，13666物理字节；9×9面板/1×1有效区连续4帧，1804字节，末像素完成与窗口边界正确 |
| Python完整回归 | 最终执行107项，44.523秒：100通过、7项因缺少Vivado明确跳过、0失败。见[Python结果](evidence/python.log) |
| 最终运行时总回归 | [15个case全部通过](evidence/runtime/summary.json)：113次CRC发布，55/56拍各36组原入口场景及25组早到状态场景；8个常规真实核心构建和2个提前OK构建，各4帧、256组完整输出及CRC一致；2个恢复构建各4个成功帧、3个无效帧 |
| 最终屏幕回归 | [9项检查全部符合预期](evidence/screen/summary.json)，含4项非法时序参数预期拒绝；覆盖8位总线、初始化、窗口、自检、模式与复位恢复 |

最终状态、退出码及来源哈希保存在`validation.json`和对应原始日志中。专项帧数、真实核心帧数和Python测试数分别统计，不混加。真实核心逐像素对照沿用冻结整数模型，没有重新搜索算法参数或改写质量门槛。本轮没有重跑完整VGA数值矩阵；完整800×480面板结果仍引用[屏幕适配阶段](../screen/README.md)的既有证据，不把本轮小尺寸检查冒称为重跑全尺寸显示。

## 复现

在仓库根目录执行，输出目录须不存在：

```powershell
python stream_video_enhance/scripts/generate_nt35510_rom.py --check
python stream_video_enhance/scripts/run_runtime_tests.py --simulator iverilog --iverilog-bin "你的Icarus目录/bin" --suite all --size 16 --output-dir stream_video_enhance/build/regression/self_check_runtime
python stream_video_enhance/scripts/run_screen_tests.py --simulator iverilog --iverilog-bin "你的Icarus目录/bin" --size small --output-dir stream_video_enhance/build/regression/self_check_screen
python -m unittest discover -s stream_video_enhance/tests -v
python stream_video_enhance/scripts/check_delivery.py
```

命令、原始日志、来源/向量哈希及必要的反例样本随证据保存；可再生编译产物不提交。旧Demo只读核对交付清单，未借本轮测试扩大其历史bit或硬件结论。

本轮未发现新的可复现屏幕RTL功能问题，但不据此宣称项目没有任何bug。物理相机VGA采集、实际屏幕接线与信号完整性、主链显示集成、全系统综合/布局布线、实机刷新及Flash冷启动仍需分别验证；没有新增整机bit或实板通过声明。
