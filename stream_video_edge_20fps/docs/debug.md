# 通用诊断

默认构建包含 VIO、被动快照、UART 和固定色条检查。普通显示无需运行这些工具。所有结果标签使用新的字母、数字、下划线或连字符组合，避免覆盖旧记录。

## UART 配对概览

在工程目录安装依赖并启动接收：

```powershell
E:\Python\python.exe -m pip install -r requirements.txt
E:\Python\python.exe pc_diag\record_pairs.py --label unique_run --frames 600 --show
```

默认且本机约定端口为 **COM10，12000000 baud，8N1**，程序明确拒绝 **COM15**。`--reference-bars` 仅用于相机固定色条参考检查。去掉 `--show` 可只保存数据。

只在摄像头 RAW 模式（包括相机色条）发送；EDGE 和内部图不发送。每 4 列、4 行采一个点：x=3,7,…,639，y=0,4,…,476，共 160×120。每点依次传输显示 Y 与前一个相邻 FIFO 字节；后者用于辨认字节相位，不是第二幅正常灰度图。LCD 仍输出完整 VGA。

| 字节位置 | 内容 |
|---|---|
| 0..7 | 固定头 `YVPAIR1!` |
| 8..11 | 帧序号 |
| 12..15 | 宽、高各 16 位 |
| 16..19 | 负载字节数，当前 38400 |
| 20..23 | 帧开始时的 100 MHz tick |
| 24..27 | FPGA 累计诊断丢包数 |
| 28..31 | 前 28 字节的 CRC32 |
| 32..38431 | 逐点交错的两通道负载 |
| 38432..38435 | 负载 CRC32 |

多字节数值按小端传输，CRC 与主机 `zlib.crc32` 一致。队列满、帧重入或配对冲突会终止诊断包并累加 dropped，不反压主链。截断包也可能触发主机负载 CRC 错误，判断时应同时查看 dropped、帧号缺口和接收异常。

输出位于 `reports/uart_pairs/<label>/`，包括原始流、逐帧数据与图片、`summary.json`。有效包数、CRC 错误数和 FPGA 帧计数分别统计，不能用其中一个代替另一个。

## VIO 与 JTAG

下面的命令均在工程目录运行，`-artifact-dir` 指向与板上 BIT 匹配的 LTX 所在目录；省略时使用 `artifacts/` 的已测版本。

```powershell
$vivadoPath = 'E:\Vivado\2025.1\Vivado\bin\vivado.bat'
& $vivadoPath -mode batch -source scripts\paired_overview_hardware.tcl -tclargs inspect -snapshot
& $vivadoPath -mode batch -source scripts\paired_overview_hardware.tcl -tclargs physical -snapshot
```

`physical` 关闭 VIO 对实体开关的接管。`reset`、`one`、`pause`、`dump` 用于复位、单帧、暂停和快照导出；`dump` 前必须暂停在完整无错帧上，防止导出期间被下一帧覆盖。

| 模式值 | 来源与输出 |
|---|---|
| 0 / 4 | 实拍 RAW / EDGE |
| 1 / 5 | 内部图 RAW / EDGE |
| 2 / 6 | 相机色条 RAW / EDGE |

```powershell
& $vivadoPath -mode batch -source scripts\paired_overview_hardware.tcl -tclargs one 0 single_unique -snapshot
& $vivadoPath -mode batch -source scripts\paired_overview_hardware.tcl -tclargs dump dump_unique -snapshot
& $vivadoPath -mode batch -source scripts\video_monitor.tcl -tclargs monitor_unique 0 500 -snapshot
& $vivadoPath -mode batch -source scripts\paired_overview_hardware.tcl -tclargs physical -snapshot
```

监测脚本记录完整帧像素数、显示队列输入/输出 CRC、帧周期、FIFO 占用及错误上下文；记录写入 `reports/lcd/runtime/`。`pause_stability.tcl` 仅接受模式 2（相机 RAW 色条），第三参数为正整数轮数、默认 10；例如 `-tclargs pause_unique 2 10 -snapshot`。`resume_current.tcl` 检查继续运行；`statistics2500.tcl` 用于带 `STAT_FRAMES` 的有限帧统计，目标数须与构建时 `-StatFrames N` 一致，省略目标数时默认 2500。主机监测与取样次数不等于硬件逐帧完整参考检查次数。

VIO 输入 0 为状态，1 为采集首错上下文/时序，2 为最后完成帧的像素数和 CRC，3 为性能计数，4/5 为快照块，6 为快照握手状态，7 为色条诊断和 UART 丢包计数低 16 位。输出 0 为虚拟开关，1 为接管/复位控制，2 为快照读取命令。

JTAG 快照 RAW 为 160×120，EDGE 为 157×118；每个样本存两字节，每块 32 个样本。摄像头 RAW 配对相邻 FIFO 字节；EDGE 或内部图配对同位置原始灰度。旧 96×96 ROI 和 16 行 strip 布局属于历史版本，不适用于当前导出。

## 独立屏幕测试图

`nt35510_bringup_top` 可单独测试屏幕接线和写入路径，不接摄像头处理链或 VIO。沿用同一 LCD 引脚约束，生成的文件放在独立输出目录：

```powershell
& $vivadoPath -mode batch -source scripts\build_lcd_pattern.tcl -tclargs E:/FPGA_Test_Work/lcd_pattern_build bit
```

末参数改为 `synth` 时仅综合；`bit` 执行实现并生成 `lcd_pattern.bit`。该 BIT 没有 VIO/LTX，不使用主工程的 `program_lcd.ps1` 下载入口。当前记录只确认此独立入口综合通过，其完整实现和硬件显示须另行验证。

独立测试程序中 SW[1:0]=0/1/2/3 分别为动态斜向灰阶、棋盘格、左右两档灰度、均匀灰度；SW15=1 在当前帧后暂停。显示区域为 630×470。这里的开关定义仅适用于独立测试 BIT，主工程仍使用[接线与控制](wiring_and_use.md)中的定义。
