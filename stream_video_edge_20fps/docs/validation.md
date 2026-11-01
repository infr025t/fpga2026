# 验证记录与证据范围

`artifacts/lcd_top_snapshot.bit` 是已经板测和写入 Flash 的历史基线，SHA256：`b33cd1017aa1dbe9d4aa03037e1271d05a9e84d0ce3b92a518d018da88a551e9`。本轮整理后的源码构建单独输出；其检查和结果见[收敛记录](consolidation_20261101.md)。历史报告保留原文、原日期，不能当作新源码已再次板测的证明。两份旧包装清单移至 `reports/evidence/packaging_20261031/`，其中的路径和哈希仅描述当时快照。

## 当前可运行的仿真

先安装 `requirements.txt`，在工程目录执行。每次换一个未使用的标签：

```powershell
E:\Python\python.exe scripts\run_lcd_tests.py core_unique tb_video_path --vga
E:\Python\python.exe scripts\test_video_capture.py camera_unique --vga
E:\Python\python.exe scripts\test_uart_pair.py uart_unique --vga
```

核心测试对照软件 Gaussian＋Sobel 参考；相机测试覆盖连续不同帧、FIFO 环绕、暂停恢复和字节配对；UART 测试检查实际串行输出和包协议。其他显示接纳、源所有权及统计检查由 `run_lcd_tests.py` 指定对应测试台。输出目录为 `reports/<label>/`，含真实 Vivado 编译、展开、运行日志及结构化结果。

仿真通过后仍需独立查看综合/实现时序、DRC 和资源报告。硬件验证应使用本次生成的 BIT/LTX，并记录哈希；像素计数与显示队列输入/输出 CRC 只能证明这两个观测点的一致性。

## 2026-11-01：收敛源码验证

[本次结构化结果](../reports/evidence/consolidation_20261101/result.json)及其同目录的 `simulation/`、`implementation/` 保存了本次证据。VGA 核心、VGA 连续采集及 UART 仿真通过；显示路径、完整源帧所有权、帧接纳和有限帧统计检查也通过。

Vivado 完整实现通过，WNS=0.664 ns、WHS=0.028 ns；使用 LUT 3773、FF 8877、BRAM 19（36 Kb 等效）、DSP 6。没有 DRC Error/Critical Warning；保留的工具/IP 和未使用网络警告见结果记录。

候选 BIT/LTX 位于 [`artifacts/consolidated_20261101/`](../artifacts/consolidated_20261101/README.md)，BIT SHA256 为 `548373f9b1e5d90eed96ef44959fef1e0df00bc58ed775d97994ca1c5f354ec8`。本候选已临时下载至 RAM，并通过下述有限硬件回归及用户动态观察，未写入 Flash；默认 `program_lcd.ps1` 仍选择 `artifacts/` 父目录的已测 BIT。

独立屏幕测试图入口已综合通过，本次没有据此宣称完整实现或上板通过。新增通用 Flash 工具仅做模拟命令检查，历史真实 Flash 操作仍按下面的记录追溯。

## 2026-11-01：收敛候选硬件复测（自动回归及用户动态观察通过）

内部 RAW/EDGE 各 50 帧参考通过；相机 RAW 色条的连续 200 个 UART 包参考、包 CRC、帧号和丢包检查通过，约 22.5077 fps。继续监测时第 324 帧触发参考错误：前 96 行共 61440 像素不符，输入/输出 CRC 同为 `589fae6c`，正确参考为 `6df0b9b5`。重连后的锁存记录一致。

用户确认该时段动过 USB 或供电，具体时刻未知，故不能归因于收敛改动，也不能据此删除失败记录。原已测 BIT 随后下载成功，重新连接后的 500 帧 RAW 色条对照通过（约 22.5077 fps）。期间 JTAG 多次中断；恢复连接、显式下载候选后，补测结果如下。Flash 未改写。详见[本轮硬件证据](../reports/evidence/consolidated_board_20261101/result.json)和[异常台账 A14、A23](anomaly_register.md)。

补测完成：

- 相机 RAW / EDGE 固定色条各 500 帧目标通过，约 22.5077 fps。RAW 硬件参考锁存与主机轮询配合，EDGE 参考由主机轮询检查，不声称逐帧全覆盖。
- 10 轮暂停／恢复通过，每轮至少 10 帧后暂停并核对色条参考和计数。
- 实拍 RAW / EDGE 各 600 帧目标通过，像素数与显示队列两端 CRC 一致，约 22.5077 fps；这不等于未知实景的逐像素真值校验。
- 实拍 UART 200 连续包，头／负载 CRC 错误、诊断丢包及帧号缺口均为 0。160×120 两字节概览不能替代全帧图像验收。
- EDGE 第一轮在检查到 598 帧后 JTAG 中断，未记通过；重连后输出已回 RAW，固件身份不确定，第二次尝试主动停止并排除。再次明确下载候选后的第三轮完成 600 帧，失败／排除记录均保留。
- 已将候选交回实体开关控制，用户已按 RAW / EDGE 移动、遮挡、近光观察问题回复“两种模式都正常”。原第 324 帧事件在本轮补测未重现，原因仍未闭合；没有宣称永久消除故障。

## 2026-10-31：改线后历史板测

原始摘要与数据见 [板测记录](../reports/evidence/rewire_20fps_20261031.md)及[结构化结果](../reports/evidence/rewire_20fps_20261031.json)。本次整理未重跑这些硬件测试。

- 固定色条 RAW/EDGE 各完成 500 帧目标，约 22.5077 fps；完整参考 CRC 检查通过。EDGE 由主机轮询检查，不能写成硬件逐帧覆盖。
- 实拍 RAW 的第二轮保存 600 个连续有效配对包，头/负载 CRC、帧号缺口和诊断丢包均为 0。第一轮 PC 在 316 张后出现 PermissionError，单独保留该记录。
- 实拍 EDGE 完成 500 帧目标，像素数和显示队列输入/输出 CRC 一致；没有逐帧实景参考，因此这项不证明内容全部正确。
- 160×120 概览筛查未见此前明显字节互换；抽样不能覆盖未导出的像素。各监测结束时排空在途帧，目标数与最终完成数可能相差 1。

实现报告、仿真日志和包装检查保留在 `reports/evidence/`，包括早期 `implementation/`、`package_cold_build/`、`simulation/` 等目录。这些名称和日志内路径反映当时运行环境，旧结论不覆盖后续源码修改。

## 2026-11-01：Flash 与用户确认

已有 BIT 以 SPIx1 格式写入板上 Flash，日志显示擦除、空白检查、编程与校验成功。实际读出的 JEDEC 字节为 `c2 20 16`；Vivado 识别为 Macronix `mx25l3273f`，使用支持项 `mx25l3273f-spi-x1_x2_x4`。之前误选 `s25fl032p` 的备份尝试失败，随后匹配型号的 4 MiB 备份成功，不能将前一次失败日志当作最终结果。

用户随后确认断电重启的 RAW 与 EDGE 显示可用。这是用户观察确认；Flash 编程日志和重启后的视觉检查分别构成证据。备份 `flash_before.bin`、MCS、Tcl 和日志均在 `E:/FPGA_Test_Work/flash_20fps_20261101`，本轮不重复复制或写入 Flash。后续可用仓库内的[通用 Flash 入口](../program_flash.ps1)，参数和动作见[工程说明](../README.md)。

## 尚未独立验证的部分

用户已将均匀横细纹归因为照明频闪。强光/快速运动时的斜向刷新区域尚未独立定位；目前无 TE 同步或双缓冲换页，不能保证无刷新撕裂。实际接线长度、节点电压、边沿和器件健康没有仪器测量。后续更改必须保留仿真、实现、板测和用户观察之间的证据边界。
