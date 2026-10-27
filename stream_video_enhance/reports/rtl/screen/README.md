# TK040F1510 / NT35510 显示驱动验证

日期：2026-10-28。[工程入口](../../../README.md) · [硬件资料及操作](../../../docs/hardware/TK040F1510.md) · [验证清单](validation.json)

本轮依据用户提供的模组、芯片、转接板和示例资料，实现独立屏幕自检。使用 100MHz 时钟、8 位 MCU8080 写接口、16 位命令及参数、RGB565 像素和 800×480 横屏。没有改动数值算法、profile、原运行时或旧 Demo，也没有把可等待总线的自检源当成主算法输出。

## 实现与优化

- `nt35510_bus8` 锁存整个16位字，命令、参数、像素均高字节先发；默认 SETUP/LOW/HOLD/GAP=2/3/2/1拍，RD常高。
- `nt35510_init` 执行可追溯的367条操作：365组寄存器写和2条单命令，共732字、1464字节。ROM由带厂商源码行号与SHA256的[profile](../../../docs/hardware/tk040f1510_profile.json)生成，`--check` 拒绝差异。
- 复位低20ms、释放后120ms、Sleep Out后120ms。乘法在64位求值，按毫秒向上取整。后一个120ms是保守策略，芯片最低要求至下一命令为5ms。
- `nt35510_window_writer` 检查矩形边界，逐字段零扩展坐标参数，支持超过255的坐标；只有末像素物理写周期结束后才报告完成。
- `nt35510_test_display` 先清黑整面板，再更新面板(84,4)…(715,475)的完整632×472有效区。每帧像素载荷596608B，相比整面板768000B减少22.32%，有效像素没有抽取或缩小，也未增加整帧缓存。
- 图案逐帧锁存；暂停完成当前帧后生效。复位立即取消发送，重新初始化和清黑完成后才开启背光。独立板级顶层为 `nt35510_bringup_top`，开关与LED见硬件说明。

默认背靠背发送每个RGB565像素需16拍，理想载荷上限6.25MPixel/s，有效区载荷约47.73ms。命令和状态开销另计；这不是实屏帧率测量。100MPixel/s核心不能直接连此接口；主链显示仍需源突发包络、有限队列和帧选择/中止设计，且不能反压计算核心。

## 实际验证

[最终回归](evidence/final_registered_reset/summary.json)由 Icarus 实际执行10项检查，全部满足预期，其中4项是必须拒绝的非法配置。其余6项正常编译/仿真均以指定PASS行和零退出完成；编译日志无警告。物理总线模型在WR上升沿接收字节，独立重组命令、坐标和RGB565，并逐像素维护GRAM，不依赖DUT内部像素握手宣称显示正确。

| 检查 | 实际结果 |
|---|---|
| [总线时序](evidence/final_registered_reset/bus/simulate.log) | 默认2/3/2/1与最低2/2/1/0配置各56字接受、52字完成、4次取消；命令/参数/红绿蓝字节顺序、源变化、间隔和短复位均通过 |
| [非法时序](evidence/final_registered_reset/summary.json) | SETUP=1、LOW=1、HOLD=0、GAP=-1各编译成功、仿真退出1，且FATAL行必须匹配对应保护；超时、编译失败或其他错误不能算通过 |
| [初始化](evidence/final_registered_reset/init/simulate.log) | 732字逐项匹配独立导出表；2次完整会话，含中途重启共2200字；随机停顿、延后完成、计数溢出、向上取整、复位/释放/Sleep Out等待通过 |
| [矩形窗口](evidence/final_registered_reset/window/simulate.log) | x700…702/y260…261，6色RGB565；2次完成、3次非法几何拒绝、1次短复位取消，非法请求无写入 |
| [实际顶层](evidence/final_registered_reset/bringup/simulate.log) | 55拍启动与按键/开关检查，复位时LCD选通安全、背光关闭、暂停状态同步 |
| [小尺寸图案](evidence/final_registered_reset/display_small/simulate.log) | 48×40面板、32×32有效区，跨16像素方格边界；四种图案、帧中切换、暂停、黑边、短复位后重启，共2次清屏、5个完成帧、21130字节 |
| [完整尺寸](evidence/final_registered_reset/display_full/simulate.log) | 800×480清屏384000点、632×472图像298304点逐点通过；含初始化/窗口共1366140个物理字节、10929451拍；暂停后无额外写入 |
| [原运行时兼容](evidence/runtime_registered_reset/summary.json) | 所有当前RTL共同编译，真实16×16核心4帧、256组RAW/BASE/selected像素和完整CRC一致，FIFO高水位1 |
| [Python回归](evidence/python.log) | 新工程103项：96通过、7项真实Vivado fixture明确跳过、0失败。包含原模型/工具契约及新增profile和运行器错误判定；模拟工具输出的单元测试不计作RTL证据 |

显示测试保留10ns时钟，把初始化 `CLK_HZ` 设为1000以缩短等待周期；该参数只缩放等待，不表示总线支持任意频率。默认100MHz的复位低/释放等待/Sleep Out等待分别为2000000/12000000/12000000拍，已独立检查。完整尺寸只跑一个灰度斜坡帧；多图案和故障场景由小尺寸覆盖，没有重复运行既有大型算法矩阵。

下图来自实际WR解码后的GRAM模型，已目视核对完整有效区与黑边，**不是实屏照片**。小尺寸最终图为复位恢复后的中灰帧，见[小尺寸模型](display_small.png)。

![800×480物理写入模型，完整632×472灰度斜坡与黑边](display_full.png)

## 修复前后证据与复现

复审发现上层原为同步复位、总线为异步复位：短脉冲可取消物理写入，却让上层继续等待被取消的完成事件。三个上层模块统一异步置位复位；移除该修复后，同一测试确实报出[FATAL反例](evidence/short_reset_red/simulation/simulate.log)，[变体及哈希](evidence/short_reset_red/summary.json)原样保存，最终版本通过相同短复位测试。复位脚另改用独立寄存器驱动，避免多位状态译码产生引脚毛刺；当前完整屏幕及原运行时兼容回归已重跑通过。此前无该寄存器的通过记录保留在 `evidence/final/`，不代替当前源码证据。另保留[首次编译失败](evidence/initial_compile_red/init/compile.log)：板级顶层的混合线网声明语法已修正，最终实际顶层编译和仿真通过。

在仓库根目录执行，输出目录必须不存在：

```powershell
python stream_video_enhance/scripts/generate_nt35510_rom.py --check
python stream_video_enhance/scripts/run_screen_tests.py --simulator iverilog --iverilog-bin "你的Icarus目录/bin" --output-dir stream_video_enhance/build/regression/screen_new --suite all --size all
python -m unittest discover -s stream_video_enhance/tests -v
python stream_video_enhance/scripts/check_delivery.py
```

运行器也支持Vivado入口，本次没有使用Vivado。各case原始命令、退出码、日志、源码/向量哈希保存在 `evidence/`；绝对路径是执行时来源，归档位置由本页链接和验证清单标明。可再生编译产物和完整PPM未提交，保留模型PNG与原PPM哈希。732字预期初始化向量体积很小，随证据保存。用户原ZIP、PDF和完整厂商C代码只在本地，不进入公共仓库。

旧Demo的861项交付哈希本轮核对通过；其86项Python为10月27日历史结果，没有在本轮重复运行。旧Demo、数值模型/profile、此前数值/运行时RTL及历史报告字节未变。

## 尚未验收的部分

屏幕仍未与主运行时或真实相机相连。实际板版、IM焊接、供电/背光、线序/XDC、引脚波形、方向/颜色及更新率需要实物验证；没有新整机bit或综合/布局布线通过结论。所给转接板未引出TE，因此 `frame_done` 只表示发送完成，不表示扫描完成，也不承诺无撕裂或原子整帧显示。资料内引脚/电气表的冲突已在硬件说明中保留。
