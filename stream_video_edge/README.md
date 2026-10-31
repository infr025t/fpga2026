# V0.4：摄像头＋平滑/Sobel＋NT35510显示
主入口为lcd_top：Basys3独立读取GYF-198 OV7670_FIFO的VGA UYVY，取Y灰度，显示完整RAW或一次平滑后的Sobel边缘。TK040F1510/NT35510为8位8080接口，横屏800×480；RAW640×480居中，EDGE630×470保留原坐标。PC只参与开发校验，正常显示不依赖PC。

本版收敛已通过短线条件下实拍的低速链路，仍为2MHz读取、约1.9fps。没有实现20fps；高帧率仅设计预想，见[后续计划](docs/high_rate_plan.md)。当前高斯边缘效果仍需调参，不把稳定显示当作画质最优。

## 构建和下载
先按[接线与使用](docs/wiring_and_use.md)连接。所有开关置0。
在此目录执行：
~~~powershell
powershell -ExecutionPolicy Bypass -File build_lcd.ps1
powershell -ExecutionPolicy Bypass -File program_lcd.ps1
~~~
已有下载文件为artifacts/lcd_top.bit及lcd_top.ltx。构建临时文件放在E:/FPGA_Test_Work/lcd_v04_build，可用-OutDir修改；Vivado默认E:/Vivado/2025.1/Vivado/bin/vivado.bat，可用-Vivado修改。下载只写FPGA配置RAM，不写配置Flash；重新断电后需重新下载。
默认控制权属于实体开关，正常运行无需JTAG或PC。VIO只提供轻量状态与测试控制，不承担图像计算。

## 显示控制
| 开关 | 含义 |
|---|---|
| SW0 | 0摄像头；1内部确定性斜纹 |
| SW1 | 通常0；复位初始化时1选择摄像头自带色条 |
| SW2 | 0完整RAW灰度；1平滑＋Sobel二值EDGE |
| SW3 | 0引导滤波ε1024/T96；1高斯平滑/T128，两者不串联 |
| SW15 | 0连拍；1不接纳新帧，当前帧排空后保留画面 |
| SW14 | 1错误页：LED15..8相机首错、LED7..0显示错误 |
| BTNC | 复位并重新初始化 |
其余开关保持0。模式按帧锁存；RAW/EDGE切换前自动清背景，避免5像素边框残影。默认阈值暂不开放LCD物理调参，串口旧入口保留手动阈值。没有自适应阈值。

## 源码组织和诊断
- rtl/core原算法未改；rtl/camera统一了已测读取修正。
- rtl/lcd_top.sv、rtl/runtime负责帧控制、核心转接、有限显示队列及首错保存；无整帧处理缓存。
- rtl/display保留原NT35510总线、初始化与窗口写入器；总线时序未提速。
- 默认构建去掉大图像快照，rtl/debug/video_snapshot.sv仅在build_lcd.ps1 -Snapshot -OutDir另一个目录时加入，生成lcd_top_snapshot.bit/ltx。该诊断配置需另行编译验证，不列为默认已上板版本。
- scripts/lcd_hardware.tcl提供program/one/pause/physical/inspect/dump；Snapshot版每次调用均需加-snapshot，dump只适用于Snapshot版。脚本的one和live会接管虚拟开关，之后用physical交回实体。
- scripts/lcd_live.tcl LABEL MODE持续监控，MODE为0 RAW、4引导EDGE、12高斯EDGE；LABEL不得复用。stop.flag或BTNC停止，首错保留。
- reports/lcd/runtime是本地运行输出，Git忽略；reports/lcd保留审阅后的发布证据。

## 验证和限制
[验收记录](reports/lcd/acceptance.json)、[验证说明](reports/validation.md)、[读取收敛说明](docs/reading_consolidation.md)区分模型、RTL、布局布线和实物证据。无图像字节猜测、像素修补或吞坏帧重试。源与送屏CRC一致不等于已验证屏幕扫描每一瞬间无撕裂。
本轮线材改善实际是全部摄像头线缩短约一半，不是仅RCK；当前RCK约20cm。后续洞洞板全组线计划≤10cm，仍须重跑基线。

## 保留的串口调试入口
rtl/edge_top.sv、build.ps1、program.ps1及pc/receive.py保留V0.3串口用途；与LCD的开关定义不同，见[串口旧入口](docs/uart_legacy.md)。共享camera已更新，但artifacts/edge_top.bit/ltx保留历史V0.3基线，不能把它当LCD程序或本轮重新构建产物。默认推荐使用build_lcd.ps1/program_lcd.ps1。PC仅COM10，绝不访问COM15；LCD正常运行不使用串口。
demo/保持原样，历史文档/记录不作为本版接线依据。
