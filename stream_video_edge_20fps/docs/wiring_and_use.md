# 当前20fps工程接线与控制

所有连接均按Basys3接口物理编号，不是Verilog数组下标。信号电平3.3V，接线操作先断电。多个Basys3 GND引脚板内已经相连，可以分别接地；注意Pmod5/11为GND、6/12为3.3V，不能接反。

## 摄像头 GYF-198 OV7670_FIFO
| 摄像头 | Basys3 |
|---|---|
| D0,D1,D2,D3 | JA1,JA2,JA3,JA4 |
| D4,D5,D6,D7 | JA7,JA8,JA9,JA10 |
| SIOC,SIOD | JC1,JC2 |
| VSYNC | JC3 |
| WEN/WR | JC4 |
| RRST | JC7 |
| RCK/RCLK | JC8 |
| 传感器RST/RESET | JC9 |
| HREF | JC10 |
| FIFO WRST | JB1（A14），独立控制，不能再短接VSYNC |
| OE、PWDN | GND |
| STR | 不接 |
| VCC/3V3 | 3.3V，例如JA6 |
| GND | Basys3 GND，例如JA5/JC5 |

RST、SIOC、SIOD为开漏驱动，需要有效上拉；上拉不等于直接短接到3.3V。摄像头信号线尽量短，RCK不留长分支。JA/JB/JC的信号线上有板载200Ω串阻，不要未经核实再叠加终端电阻。没有新增PCLK/WCK或RE连接。

## TK040F1510/NT35510转接板
模块已由用户改焊为8位8080模式。
| LCD | Basys3 |
|---|---|
| D0,D1,D2,D3 | JXADC1,2,3,4 |
| D4,D5,D6,D7 | JXADC7,8,9,10 |
| CS,RS,WR | JB2,JB3,JB4 |
| RD,RST,BL | JB7,JB8,JB9 |
| 3V3,GND | JB6,JB5 |
| D8～D23、其余未使用功能 | 不接 |

JB2现在用于LCD CS，不再用于旧RCK观测分支；JC8直连相机RCK。当前没有TE接入或扫描同步逻辑。

## 开关
| 操作 | 效果 |
|---|---|
| SW0=0、SW1=0 | 实拍，其他无关开关保持0 |
| SW2=0 / 1 | RAW灰度 / 高斯＋Sobel |
| SW15=0 / 1 | 连拍 / 当前帧完成后暂停 |
| SW0=1 | 内部确定性斜纹 |
| SW1=1后BTNC | 复位后配置相机色条；恢复实拍需SW1=0后BTNC |
| BTNC | 复位相机和FPGA流程 |
| SW14=1 | LED15..8相机首错，LED7..0显示错误 |

program_lcd.ps1下载后交回实体开关。若运行自动JTAG脚本接管过，请用paired_overview_hardware.tcl的physical -snapshot动作交还。RAW为640×480，EDGE为630×470，均居中显示在800×480屏上；边缘模式清背景可能短暂闪黑。
