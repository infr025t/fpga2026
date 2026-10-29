# 接线与使用

板卡：Basys3/XC7A35T，100 MHz；相机GYF-198 OV7670_FIFO/AL422；屏幕保留TK040F1510/NT35510的8位8080驱动。

## 现有相机接线

使用已验收的JA/JC接线，并增加独立WRST至JB1。供电和IO保持原方案；以下FPGA脚号均为Basys3封装引脚，与constraints/basys3_camera_uart.xdc一致。

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

## 物理开关

| 开关 | 含义 |
| --- | --- |
| SW0 | 0相机，1内部确定性VGA图案 |
| SW1 | 0 RAW原始亮度，1 EDGE |
| SW2 | 0一次引导滤波，1一次3×3加权平滑 |
| SW12:4 | 全0使用该滤波器默认阈值；非0值N选择min(4N,2040) |
| SW14 | 0正常LED，1错误页；高8位为组合错误码 |
| SW15 | 0→1触发一次；下一张先拨回0 |
| SW3/SW13 | 未使用，保持0 |
| BTNC | 中止并重新初始化；错误后必须复位再试 |

默认阈值：引导滤波ε1024、T96；加权平滑T128（ε64仅作协议占位，不参与加权滤波）。例如SW12:4表示16时，T=64。核心接口本身支持0..2040的整数阈值，物理开关按4递增；自动采集可传--threshold64等参数，不是逐帧自动阈值算法。

正常LED：LED0就绪，LED1相机采集中，LED2处理/串口忙，LED3内部源，LED4 EDGE模式，LED5加权平滑，LED14完成，LED15错误/请求拒绝。

## 下载与接收

在本目录运行，安装依赖：`E:\Python\python.exe -m pip install -r requirements.txt`。

```powershell
powershell -ExecutionPolicy Bypass -File program.ps1
powershell -ExecutionPolicy Bypass -File receive_one.ps1
```

下载脚本默认释放JTAG虚拟开关，使实体SW有效。所有SW先置0、BTNC复位、LED0亮后，先启动接收程序，再将SW15从0拨到1。每次只传一张；结束后COM10释放，窗口保留最后一张。RAW也是Y灰度，并非RGB彩色原图。输出原生630×470，另存640×480五像素黑边画布；没有缩小或在PC计算边缘。

自动内部自检／四组合各一张：

```powershell
E:\Python\python.exe -B pc/receive.py --auto --source internal --rounds 1
```

自动相机50张验收复现（四组合循环，共50张）：

```powershell
E:\Python\python.exe -B pc/receive.py --auto --source camera --frames 50
```

`--frames N`支持精确1..100张；`--rounds N`保留四组合一轮的方式，二者互斥。自动模式通过VIO接管开关，不需要拨实体SW。完成后若转回手动，运行`vivado.bat -mode batch -source scripts/release_switches.tcl`，或重新运行program.tcl。自动程序出现明确错误即停止，没有隐藏重连或自动补拍。

默认新采集输出位于E:/FPGA_Test_Work/edge_v03_work/capture_时间戳。文件按GUIDED/GAUSSIAN和RAW/EDGE分目录保存；PNG、BIN、WIRE、JSON相互对应。需检查partial.wire、rejected包或error.json时，不将它们当成成功图片。

## 显示屏保留范围

见[screen_interface.md](screen_interface.md)。该测试bit没有LCD未知引脚的分配，也没有把独立屏幕自检等同主链显示完成。实屏未联合验证；接屏之前不要猜测引脚或强行添加XDC消除未约束告警。

## 相机与诊断约定

AEC自动曝光、AGC自动增益、AWB自动白平衡均开启，初始化COM8=E7，不执行初始化后的冻结。FIFO采集前在一个HREF内执行WRST，选定下一完整帧；读取期间WRST保持释放，后续两行沿同一写地址追加以提交尾部缓存，不切换COM10极性。读复位预取的U0按已消费字节计数，释放后首拍Y0送入核心。

同步后的VSYNC低电平连续64个100MHz周期才接受，正常上升沿不作同等延迟；仍要求480行。提前采样／正式采样对比暂留作诊断，不增加读取脉冲。`metrics_*.json`低字起依次为行数、已消费字节数、帧周期数、帧结束时读取位置、最小／最大HREF高周期数、最大估算积压、读取暂停周期数；`sync_*.json`依次为最近有效低脉冲宽度、短脉冲计数、最大短脉冲宽度、错误结束脉冲宽度。系统周期10ns，字节数包括预取首字节。

出错保留failure_snapshot.json、partial.wire和error.json，不补拍。HREF统计不是实际WCK字节测量。当前2MHz是验证工作点，尚未测出读取速率上限。
