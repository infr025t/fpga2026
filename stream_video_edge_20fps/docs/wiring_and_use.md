# 当前接线与控制

以下均为 Basys 3 接口的物理编号，不是 Verilog 数组下标。接线操作先断电。Pmod 5/11 为 GND、6/12 为 3.3 V；多个 GND 在板内相连，可分别为模块提供回流。模块供电为 3.3 V、FPGA 端口按 LVCMOS33 配置，这不代表摄像头每个信号节点的实际高电平都为 3.3 V。

## 摄像头 GYF-198 OV7670_FIFO

| 摄像头 | Basys 3 |
|---|---|
| D0,D1,D2,D3 | JA1,JA2,JA3,JA4 |
| D4,D5,D6,D7 | JA7,JA8,JA9,JA10 |
| SIOC,SIOD | JC1,JC2 |
| VSYNC | JC3 |
| WEN/WR | JC4 |
| RRST | JC7 |
| RCK/RCLK | JC8 |
| 传感器 RST/RESET | JC9 |
| HREF | JC10 |
| FIFO WRST | JB1（A14），独立控制，不能短接 VSYNC |
| OE、PWDN | GND |
| STR | 不接 |
| VCC/3V3 | 3.3 V，例如 JA6 |
| GND | Basys 3 GND，例如 JA5/JC5 |

传感器 **RST、SIOC、SIOD** 由 FPGA 开漏驱动。当前用户接线记录为三路各自采用 `3.3 V → 4.7 kΩ → 信号节点 → 22 kΩ → GND`。忽略输入负载与模块其他元件时，高电平计算值为 `3.3×22/(4.7+22)≈2.72 V`；这是外接电阻网络的估算，不是节点实测电压或所有摄像头 I/O 的电压结论。传感器 RST 与 **JB1 的 FIFO WRST** 是不同信号，不能混接。

相机信号总路径尽量短，RCK 与 GND 伴随布线，不留长观测分支；LCD 背光回流不要串经摄像头细地线。JA/JB/JC 信号有板载 200 Ω 串阻，不能未经核实再叠加终端电阻。既有依据为 [Basys 3 Rev.C 原理图](https://digilent.com/reference/_media/basys3:basys3_sch.pdf)；当前总线长度、边沿和器件健康未做仪器测量。没有新增 PCLK/WCK 或 RE 连接。

## TK040F1510/NT35510 转接板

模块已由用户改焊为八位 8080 模式。

| LCD | Basys 3 |
|---|---|
| D0,D1,D2,D3 | JXADC1,2,3,4 |
| D4,D5,D6,D7 | JXADC7,8,9,10 |
| CS,RS,WR | JB2,JB3,JB4 |
| RD,RST,BL | JB7,JB8,JB9 |
| 3V3,GND | JB6,JB5 |
| D8～D23、其余未使用功能 | 不接 |

JB2 用于 LCD CS，JC8 直连相机 RCK。当前没有 TE 接入或扫描同步逻辑。

## 开关

| 操作 | 效果 |
|---|---|
| SW0=0、SW1=0 | 实拍，其他无关开关保持 0 |
| SW2=0 / 1 | RAW 灰度 / Gaussian＋Sobel |
| SW15=0 / 1 | 连拍 / 当前帧完成后暂停 |
| SW0=1 | 内部确定性斜纹 |
| SW1=1 后 BTNC | 复位后配置相机色条；恢复实拍需 SW1=0 后 BTNC |
| BTNC | 复位相机和 FPGA 流程 |
| SW14=1 | LED15..8 为相机首错，LED7..0 为显示错误 |

`program_lcd.ps1` 下载后交回实体开关。JTAG 自动脚本接管后，用 `paired_overview_hardware.tcl physical -snapshot` 交还，完整调用见[调试说明](debug.md)。RAW 为 640×480，EDGE 为 630×470，均居中显示；模式切换清背景时可能短暂闪黑。Flash 自启动后等待相机配置、预热与屏幕初始化完成再观察。
