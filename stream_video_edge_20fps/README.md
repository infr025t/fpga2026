# VGA Gaussian＋Sobel 视频工程

Basys 3（XC7A35T）＋GYF-198 OV7670_FIFO/AL422B＋TK040F1510/NT35510 八位 8080 屏。FPGA 独立完成 VGA 读取、RAW 灰度显示或一次 3×3 Gaussian＋Sobel；正常显示不依赖 PC。RAW 为 640×480，EDGE 为 630×470、固定阈值 128，居中显示在 800×480 屏上。

本工程作为持续优化基线，保留内部测试图、相机色条、UART、VIO、首错锁存和完整性保护。旧低速工程及一次性实验入口已收敛；目录名 `stream_video_edge_20fps` 保留。架构与时序见[设计说明](docs/spec.md)，本轮范围与检查见[收敛记录](docs/consolidation_20261101.md)。

## 使用已测程序

2026-11-01 用户确认 Flash 断电自启动后 RAW/EDGE 可用。当前板上 Flash 保持该程序。需要临时重新下载已测程序到 FPGA 配置 RAM 时，在本目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\program_lcd.ps1
```

脚本使用 Vivado 2025.1，连接 Basys 3 `210183BCBF83A`，下载 `artifacts/lcd_top_snapshot.bit` 及对应 LTX，随后交回实体开关。此命令不写 Flash；断电后从已有 Flash 程序启动。

已测 BIT 的 SHA256 为 `b33cd1017aa1dbe9d4aa03037e1271d05a9e84d0ce3b92a518d018da88a551e9`。`artifacts/` 父目录代表历史硬件基线。收敛后候选位于 [`artifacts/consolidated_20261101/`](artifacts/consolidated_20261101/README.md)，已通过仿真及完整实现，已进行部分板测，完整验收尚未完成；默认下载入口仍选择父目录的已测版本。

## 从源码构建

```powershell
powershell -ExecutionPolicy Bypass -File .\build_lcd.ps1 -Snapshot -OutDir E:\FPGA_Test_Work\edge20fps_build
```

完整入口创建 Vivado 工程与 VIO，执行综合、布局布线并生成 BIT/LTX。默认启用 Snapshot 诊断；新产物和报告只写入指定 `OutDir`，不会覆盖 `artifacts/`。输出目录应在源码树之外。`-Vivado` 可指定工具路径；`-StatFrames N` 可生成完成 N 帧后停止的统计版本，默认 0 为持续运行。

若要把指定新构建下载到配置 RAM，显式选择其目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\program_lcd.ps1 -ArtifactDir E:\FPGA_Test_Work\edge20fps_build
```

下载新构建不会更新已有 Flash。仓库附带的收敛候选可用 `-ArtifactDir .\artifacts\consolidated_20261101` 选择，板测进展见[验证记录](docs/validation.md)。

## Flash 工具

通用入口 [`program_flash.ps1`](program_flash.ps1) 提供 Prepare、Backup、Program 三个动作；默认 Prepare，仅离线生成 SPIx1 MCS。下面是对同一外部输出目录执行备份和写入的用法，本次整理没有执行这些硬件动作：

```powershell
powershell -ExecutionPolicy Bypass -File .\program_flash.ps1 -Action Prepare -OutDir E:\FPGA_Test_Work\edge20fps_flash
powershell -ExecutionPolicy Bypass -File .\program_flash.ps1 -Action Backup -OutDir E:\FPGA_Test_Work\edge20fps_flash
powershell -ExecutionPolicy Bypass -File .\program_flash.ps1 -Action Program -OutDir E:\FPGA_Test_Work\edge20fps_flash
```

`-ArtifactDir` 选择要写入的 `lcd_top_snapshot.bit`，默认是 `artifacts/` 已测版本。Backup 保存完整 4 MiB `flash_before.bin` 并拒绝覆盖；Program 要求该备份存在，重新生成 MCS 后执行擦除、空白检查、写入与校验。默认 `-Part mx25l3273f-spi-x1_x2_x4`、`-TargetSerial 210183BCBF83A`，保留 Vivado 器件 ID 检查。

Backup/Program 使用临时 Flash 访问配置，完成后恢复 `-RestoreArtifactDir` 的 BIT/LTX（默认仍为 `artifacts/` 已测 RAM 程序）。因此 Program 后的 RAM 显示并不证明新 Flash 镜像已经自启动，须另做断电重启检查。新通用工具本轮只做模拟命令检查，未连接硬件。

2026-11-01 已完成的 Flash 备份和日志仍在 `E:/FPGA_Test_Work/flash_20fps_20261101`。备份和运行产物留在外部目录，不提交到源码仓库。

## 接线与操作

按[接线与使用](docs/wiring_and_use.md)连接。SW0=0、SW1=0 使用真实摄像头；SW2=0 显示 RAW，SW2=1 显示 Gaussian＋Sobel；SW15=1 在当前帧完成后暂停。BTNC 复位初始化。SW0=1 选择内部图，SW1 在复位期间选择相机色条，SW14 切换错误 LED 页，其余开关保持 0。

## 调试与验证

可选串口诊断通过 COM10、12 Mbaud 回传 160×120 双字节概览，禁止使用 COM15。VIO 快照、连续监测、暂停恢复和串口协议见[调试说明](docs/debug.md)。诊断不反压核心，LCD 仍显示完整分辨率。

[验证说明](docs/validation.md)列出本次通过的 VGA、显示、帧接纳、源所有权与统计仿真，以及 2026-10-31 的历史板测和 2026-11-01 的 Flash 记录。本次完整实现 WNS=0.664 ns、WHS=0.028 ns，结果见[结构化证据](reports/evidence/consolidation_20261101/result.json)。仿真、实现时序、板上 CRC、面板画质分别记录；新构建不能直接继承旧 BIT 的硬件结论。当前未接 TE，也未做显示双缓冲，快速运动下的刷新界线尚未独立定位。

历史及当前未解决问题集中记录在[异常台账](docs/anomaly_register.md)，包括移动暗条纹、斜向刷新分界线、采集错位和连接故障。
