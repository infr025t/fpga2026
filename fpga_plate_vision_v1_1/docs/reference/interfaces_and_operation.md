# 接口、接线与运行操作

本页以当前[约束文件](../../project/constraints/basys3_camera_lcd.xdc)、[顶层](../../project/rtl/top/lcd_top.sv)及[模式译码](../../project/rtl/top/display_mode_control.sv)为准。接口物理编号与旧接线记录逐项对照，但**开关定义已更新**：SW4选择OCR并优先于SW3，SW3选择EDGE，SW5选择自主OCR字符极性，SW2保留不用。本页适用于v1.1源码；实际BIT身份见[当前验证](current_validation.md)。

## 摄像头接口

对象为现有GYF-198 OV7670_FIFO模块。下表方向相对于FPGA；JA/JC等数字是连接器物理针号，`cam_data[n]`才是RTL位号。信号引脚均为LVCMOS33，供电地线不由XDC描述。

| 模块信号 | 顶层端口 | 方向 | Basys 3物理针 | FPGA封装引脚 |
|---|---|---|---|---|
| D0 | cam_data[0] | 输入 | JA1 | J1 |
| D1 | cam_data[1] | 输入 | JA2 | L2 |
| D2 | cam_data[2] | 输入 | JA3 | J2 |
| D3 | cam_data[3] | 输入 | JA4 | G2 |
| D4 | cam_data[4] | 输入 | JA7 | H1 |
| D5 | cam_data[5] | 输入 | JA8 | K2 |
| D6 | cam_data[6] | 输入 | JA9 | H2 |
| D7 | cam_data[7] | 输入 | JA10 | G3 |
| SIOC | cam_sioc | 开漏/高阻 | JC1 | K17 |
| SIOD | cam_siod | 双向开漏 | JC2 | M18 |
| VSYNC | cam_vsync | 输入 | JC3 | N17 |
| WEN/WR | cam_wen | 输出 | JC4 | P18 |
| FIFO RRST | cam_rrst_n | 输出，低有效复位 | JC7 | L17 |
| FIFO RCK/RCLK | cam_rclk | 输出 | JC8 | M19 |
| 传感器RST/RESET | cam_rst_n | 开漏，低有效复位 | JC9 | P17 |
| HREF | cam_href | 输入，约束启用下拉 | JC10 | R18 |
| FIFO WRST | cam_wrst_n | 输出，低有效复位 | JB1 | A14 |

现有接线记录中OE、PWDN接GND，STR不接；没有新增PCLK/WCK或独立RE观测线。模块VCC使用3.3V、与Basys 3共地，例如JA6供电、JA5/JC5接地。JA/JB/JC物理5和11为GND、6和12为3.3V；不得把连接器物理编号误当数组下标。上述模块辅助脚/供电属于实物接线记录，XDC本身不能检测它们是否真的接对；调整前先断电核对模块丝印。

**传感器RST与FIFO WRST不同。** 当前WRST由JB1独立控制，不能再与VSYNC短接，也不能与JC9的传感器复位混接。[连续采集驱动](../../project/rtl/drivers/camera/camera_fifo_video.sv)采用跨多场连续写入周期与行信用，AL422B容量393216字节小于完整VGA YUV422的614400字节，不能改回整帧写完再慢读的假设。

顶层对RST、SIOC、SIOD仅输出0或高阻Z；释放高阻不等于主动输出高电平，需要有效上拉。当前XDC没有给这三路启用内部PULLUP。旧实物记录采用每路`3.3V → 4.7kΩ → 信号节点 → 22kΩ → GND`，忽略其余负载计算约2.72V；这只解释已有网络，不能作为所有模块的通用方案，也不是节点实测电压。已有上拉、模块输入电压范围和实际高电平须按实物核定，不能因为SCCB有ACK就认定全部电气裕量合格。[开漏实现](../../project/rtl/drivers/camera/ov7670_config.sv)、[历史异常](anomaly_register.md)。

保持整组相机信号短而连贯，RCK与地回流相邻，LCD背光回流不要串经相机细地线。历史缩线改变了整组连线，不能写成仅RCK单线修复。当前RCLK周期参数6（100MHz下约16.667MHz）、SLOW驱动、单次采样在发沿后40ns、`Y_BYTE=0`；约束外部23ns加片内5ns共28ns是预算，不是线缆实测。实际字节选择以采集驱动参数为准，不依据图像内容自动互换Y/UV。

## LCD接口

现有TK040F1510/NT35510转接板使用8位8080接口，实物IM0=IM1=0。只接D0至D7不会自动改变模块总线模式；核对实物IM丝印，不照搬另一版跳阻位置。

| LCD信号 | 顶层端口 | Basys 3物理针 | FPGA封装引脚 |
|---|---|---|---|
| D0 | lcd_data[0] | JXADC1 | J3 |
| D1 | lcd_data[1] | JXADC2 | L3 |
| D2 | lcd_data[2] | JXADC3 | M2 |
| D3 | lcd_data[3] | JXADC4 | N2 |
| D4 | lcd_data[4] | JXADC7 | K3 |
| D5 | lcd_data[5] | JXADC8 | M3 |
| D6 | lcd_data[6] | JXADC9 | M1 |
| D7 | lcd_data[7] | JXADC10 | N1 |
| CS | lcd_cs_n | JB2 | A16 |
| RS | lcd_rs | JB3 | B15 |
| WR | lcd_wr_n | JB4 | B16 |
| RD | lcd_rd_n | JB7 | A15 |
| RST | lcd_reset_n | JB8 | A17 |
| BL | lcd_bl | JB9 | C15 |

现有模块3V3/GND接JB6/JB5；D8至D23及其余未使用功能不接。当前无TE接入或扫描同步逻辑。所有LCD端口为输出，DRIVE=4、SLEW=SLOW；[总线驱动](../../project/rtl/drivers/display/nt35510_bus8.sv)将RD保持高，不执行屏幕读回。RGB565像素分两次8位写出，顶层总线时序为SETUP/LOW/HOLD/GAP=2/2/2/0个100MHz周期，不能把8位总线误写成8位像素格式。[显示接收端](../../project/rtl/video/video_lcd_sink.sv)在初始化和背景清屏完成后开启BL。

RAW为640×480，居中放在800×480屏幕，左边界x=80；EDGE裁边后630×470，左上角为(85,5)。切换尺寸需要清背景，短暂黑屏属于该过程。OCR显示RAW并叠加实际定位绿框和最近结果；RAW/EDGE退出OCR时角落为OFF，不保留旧识别答案。队列CRC核对叠字前像素，不等于最终屏幕接收CRC。

## 三种正常工作模式

先保证SW0=SW1=SW12=SW13=SW14=SW15=0，并取消VIO覆盖。其余保留开关置0。

| SW4 | SW3 | 模式 | 屏幕与识别行为 |
|---:|---:|---|---|
| 0 | 0 | RAW | 相机灰度视频；自主识别关闭 |
| 0 | 1 | EDGE | Gaussian＋Sobel视频；自主识别关闭 |
| 1 | 0或1 | OCR | RAW视频与自主字符识别；SW4优先，SW3不再选择EDGE |

SW5=0为暗字（默认），SW5=1为白字，蓝底白字牌面使用SW4=1、SW5=1。SW5只影响自主OCR的分割与归一化，不反相LCD背景、原始小图或定位输入。OCR中切换SW5会中止旧识别任务并清除旧文字和ROI，再从下一次接纳的完整源帧开始；无需按BTNC。人工上传的旋转/反相仍由请求flags控制。

全开关0对应RAW。SW2仍连接实体输入，但当前没有业务用途，拨动不会替代SW3。正常切换不需要BTNC；视频请求在帧边界接纳，识别开关及人工/诊断模式变化会中止旧识别任务并清除旧结果。若处于SW15暂停，显示要恢复接纳帧后才更新。

OCR按完整640×480源帧抽样成160×120灰度小图，再定位、分割、归一化、CNN和有符号argmax。忙时跳过新源帧，视频不等识别；PC断开也不停止计算。暗字与白字选择共用现有定位器，具体牌面、背景和对比度条件见[白字支持](white_character_support.md)；前缀几何排除和细桥拆分保持原规则。

[屏幕叠字](../../project/rtl/video/plate_text_overlay.sv)的WAIT表示等待新完整结果，NONE表示本次没有字符，ERR表示本次任务报错，OFF表示自主识别关闭。正常显示前8个字母/数字，更多字符第9格显示`+`；分割与串口上限仍为64。显示的是最近完成结果，不保证与当前视频帧同时采集；文字在视频帧边界更新，暂停时也暂停显示更新。

## 全部开关和复位

| 控制 | FPGA引脚 | 当前作用 |
|---|---|---|
| SW0 | V17 | 1选内部确定性图；0选相机。内部图可用于视频链诊断，不是相机出图证明 |
| SW1 | V16 | 0实拍；1相机固定色条。改变后按BTNC，使启动阶段重新配置 |
| SW2 | W16 | 保留，无业务作用；旧版SW2切EDGE的说明不适用 |
| SW3 | W17 | SW4=0时：0 RAW，1 EDGE |
| SW4 | W15 | 1请求OCR且优先于SW3；实际AUTO还要求SW12=SW13=0 |
| SW5 | V15 | 自主OCR字符极性：0暗字（默认），1白字；RAW/EDGE和人工协议不受影响 |
| SW6至SW11 | W14/W13/V2/T3/T2/R3 | 保留，当前顶层未使用 |
| SW12 | W2 | SW13=0时，1选择相邻字节UART诊断并关闭AUTO；正常OCR置0 |
| SW13 | U1 | 1人工上传/回放模式，优先于SW12，关闭AUTO；可与显示模式独立使用 |
| SW14 | T1 | 1将LED改为两个8位错误码；不切换图像 |
| SW15 | R2 | 1停止接纳新视频帧，已接纳帧排空后暂停；0恢复连续视频 |
| BTNC | U18 | 高有效系统复位，并重新初始化相机和LCD；即使VIO接管开关，实体BTNC仍参与复位 |
| clk100 | W5 | 板载100MHz时钟输入，约束周期10ns |

SW12诊断包要求真实相机RAW路径；使用时SW0=0、SW3=SW4=0、SW13=0。若同时选择EDGE，当前诊断上传启动条件不成立；若选内部图，也没有有效相机配对图，不要将无包误判为串口坏。人工回放通过UART接收原图和请求，与自主模式“PC只收不发”是不同工作方式。

[相机启动模块](../../project/rtl/drivers/camera/camera_startup.sv)在100MHz下先保持传感器复位约10ms，配置复位约20ms，再等待SCCB完成及约2s预热；LCD独立初始化。SW1仅在启动复位保持窗口锁存，运行时单独拨SW1不会立刻改相机寄存器。SW0内部图可以绕过相机ready条件，故“内部图正常”不能证明相机初始化成功。

## LED含义

SW14=0时，LED15至LED0按下表显示。LED不是OCR正确率指示器，初始化亮灯也不能替代实物画面检查。

| LED | FPGA引脚 | 亮灯/字段含义 |
|---|---|---|
| 15 | L1 | 综合错误非0：配置、固定参考、相机首错或显示错误 |
| 14:11 | P1/N3/P3/U3 | 显示完成帧计数低4位，以二进制循环变化 |
| 10 | W3 | 显示错误非0 |
| 9 | V3 | 已锁存相机错误非0 |
| 8 | V13 | SCCB配置错误 |
| 7 | V14 | 当前有效SW15暂停请求 |
| 6 | U14 | 当前已接纳帧来自内部图 |
| 5 | U15 | 帧完成标记；下一次接纳帧会清除 |
| 4 | W18 | LCD接收/绘制路径busy |
| 3 | V19 | 相机采集busy |
| 2 | U19 | 背景清屏完成 |
| 1 | E19 | LCD初始化完成 |
| 0 | U16 | 当前源与显示接收端ready；不表示一定已显示正确图像 |

SW14=1时，LED15:8显示`observed_cap_error[7:0]`，LED7:0显示`sink_error[7:0]`，高位LED对应错误码高位。此视图不包含独立的SCCB错误/参考错误指示；需要同时查看普通LED或VIO状态。相机首错由[锁存模块](../../project/rtl/video/capture_fault_latch.sv)保留，复位会清除现场，排错前先记录。

## UART、JTAG与启动存储

板载USB-UART端口：FPGA TX=`uart_txd`/A18，FPGA RX=`uart_rxd`/B18（启用上拉）。不需要外接UART线。本轮仅允许使用**COM10、12,000,000 baud、8N1、无流控**；自主观察器CLI强制COM10，部分历史人工工具虽接受其他端口，本轮不使用，COM15禁止访问。UART与JTAG虽经同一USB连接提供服务，职责不同：UART传观测/人工协议，JTAG下载配置RAM或读写VIO，串口收到包不证明JTAG连接稳定，JTAG断连也不直接证明视频核心停止。

JTAG下载`.bit`到FPGA配置RAM，断电丢失；QSPI Flash是非易失启动存储。本版已经通过独立Flash脚本完成备份、擦除、写入和校验，并从QSPI重新加载后确认视频帧计数推进、错误码为0。JP1保持QSPI，开机即可运行本版。[scripts/hardware.tcl](../../project/scripts/hardware.tcl)的`program`仍只配置RAM；Flash步骤和证据见[Flash与启动](flash_and_startup.md)。

脚本锁定Basys 3目标序列标识`210183BCBF83A`及`xc7a35t_0`。当前硬件脚本默认使用发布根目录`release/`中的BIT/LTX；对其他构建必须显式传入目录，并使用该目录成对BIT/LTX，不能混用历史探针文件。当前接口控制属于新源码，旧build_split仍保留其旧开关定义，不能将本页操作表直接套到旧BIT。

## VIO覆盖与操作入口

VIO的`debug_control[0]=1`时，16位virtual_sw整体替代实体开关；所以实体SW15或SW3看似无效时先检查覆盖状态。`debug_control[1]`可请求复位，实体BTNC始终有效。`physical`将整个debug_control清0，恢复实体控制；它不重新下载程序，也不写Flash。下面命令在`project/`目录执行，Vivado可执行文件需已加入PATH。

```powershell
vivado -mode batch -source scripts/hardware.tcl -tclargs physical ../release
```

| hardware.tcl动作 | 当前行为 |
|---|---|
| probe | 查找指定板卡，不下载 |
| program | 由release或显式指定目录加载BIT/LTX并配置RAM；不保证取消原VIO覆盖，结束后按需physical |
| status | 读取VIO输入探针，不改变开关覆盖 |
| auto | virtual_sw=0x0010，启用覆盖：真实相机RAW＋暗字OCR |
| auto_white | virtual_sw=0x0030，启用覆盖：真实相机RAW＋白字OCR |
| raw | virtual_sw=0x0000，启用覆盖：真实相机RAW，自主识别关闭 |
| edge | virtual_sw=0x0008，启用覆盖：EDGE，自主识别关闭 |
| internal | virtual_sw=0x0001，启用覆盖：内部RAW图 |
| pair或camera | virtual_sw=0x1000，启用覆盖：相邻字节诊断；camera是旧入口别名，不是OCR模式 |
| cnn | virtual_sw=0x2000，启用覆盖：人工回放模式 |
| physical | 清除VIO控制，恢复实体开关 |

脚本raw动作用于自动验收；正常RAW可用physical后实体全0。动作设置virtual_sw不会主动重新配置相机，若上一状态为SW1色条，改回实拍仍须在SW1=0生效后复位；不可把脚本名称当作相机寄存器读回证明。

自主识别仅需板卡运行OCR；PC观察为可选项。[观察器](../../project/pc/observe_auto.py)先接收并落盘，关闭串口后再做整数参考核验，不上传图像或启动命令：

```powershell
python pc/observe_auto.py --port COM10 --baud 12000000 --frames 100 --timeout 60 --out reports/auto_capture_01
```

只有现场号码确实已知且保持该号码时，才追加例如`--truth BD12345`；该参数仅在预测后评分，不参与推理。输出目录须为新目录，已有`wire.bin`或`summary.json`会拒绝覆盖。离线复核不打开串口：

```powershell
python pc/observe_auto.py --wire reports/auto_capture_01/wire.bin --frames 100 --out reports/auto_replay_01
```

保存完整组数、首尾残组、CRC拒绝、板上采集错误、发布丢弃和场景说明。观察器`passed=true`表示完整组符合参考算法，并不单独证明号码正确；识别忙主动跳源帧也不是视频丢帧。具体故障与已有验证边界见[异常台账](anomaly_register.md)和[历史证据](historical_evidence.md)。

当前OCR绿框来自最近一次实际定位ROI，颜色不代表识别成功；无区域或采集中止后在帧边界撤框，运动时有定位滞后。详见[区域框说明](roi_overlay_and_options.md)。
