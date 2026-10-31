# V0.4 LCD接线与使用
板卡Basys3/XC7A35T，摄像头GYF-198 OV7670_FIFO/AL422，屏幕TK040F1510/NT35510。
全部IO为3.3V，共地。断电接线；LCD转接板必须已设为8位8080（当前实物已改焊）。
## 摄像头
| 相机信号 | FPGA封装脚 | 板上接口 |
| --- | --- | --- |
| D0..D7 | J1,L2,J2,G2,H1,K2,H2,G3 | JA1,2,3,4,7,8,9,10 |
| SIOC | K17 | JC1 |
| SIOD | M18 | JC2 |
| VSYNC | N17 | JC3 |
| WEN/WR | P18 | JC4 |
| RRST | L17 | JC7 |
| RCLK/RCK | M19 | JC8 |
| RESET/RST | P17 | JC9 |
| HREF | R18 | JC10 |
| WRST（FIFO写复位） | A14 | JB1 |

相机WRST接JB1，必须与VSYNC断开；VSYNC仍接JC3。RESET/RST与WRST不同，RESET原接线保留。OE与PWDN接地；STR为STROBE，当前不连接。USB接Basys3的PROG/UART口。PC仅使用COM10，12,000,000 baud、8N1；不访问COM15。


这轮是全部摄像头线缩短约一半，RCK约20cm，不能单独归因于RCK。避免分支和面包板；洞洞板全组≤10cm是后续目标，需保持良好地回流。
## LCD：双排40针转接板
| 屏幕信号 | Basys3接口 | FPGA脚 |
|---|---|---|
| D00,D01,D02,D03 | JXADC1,2,3,4 | J3,L3,M2,N2 |
| D04,D05,D06,D07 | JXADC7,8,9,10 | K3,M3,M1,N1 |
| CS | JB2 | A16 |
| RS | JB3 | B15 |
| WR | JB4 | B16 |
| RD | JB7 | A15 |
| RST | JB8 | A17 |
| BL | JB9 | C15 |
| 3V3 | JB6 | 板载3.3V |
| GND | JB5 | 地 |
摄像头WRST仍为JB1。JB2已用于LCD CS，不再接RCK观测支路。D08..D23不接；D00就是数据bit0，不能按物理排针顺序猜线序。
## 下载与操作
所有开关先0，执行program_lcd.ps1后自动交回实体开关：SW0相机/内部源，SW2 RAW/EDGE，SW3引导/高斯，SW15暂停/继续。暂停只停止下一帧，当前帧完整排空。SW14查看错误页；异常先保留现场，BTNC会清空首错并重新初始化。
启动先清屏；相机初始化和预热约数秒。RAW在x80..719/y0..479，EDGE在x85..714/y5..474；屏幕接收原尺寸图，未缩成QVGA。模式切换会先清屏，可能短暂黑屏。
正常LED0就绪，LED1屏幕初始化完成，LED2背景清理完成，LED3采集忙，LED4显示忙，LED5帧完成，LED6内部源，LED7暂停；LED8相机配置错误，LED9相机首错，LED10显示错误，LED14..11为帧计数低4位，LED15任意错误。
当前仍2MHz、约1.9fps；不标为视频20fps。高斯边缘效果待优化。
