# VGA 20fps：当前可构建、可下载的测试工程

Basys 3（XC7A35T）＋GYF-198 OV7670_FIFO/AL422B＋TK040F1510/NT35510八位8080屏。FPGA独立完成VGA读取、RAW灰度显示或一次3×3高斯平滑＋Sobel；正常显示不依赖PC。RAW为640×480、左右各80像素黑边；EDGE为630×470、阈值128。

本次是当前测试工程的直接整理，不是算法或读取逻辑收敛。26个RTL文件均与E:/FPGA_Test_Work/video20fps_20261030对应文件逐字节相同；四个数值核心文件也与低速基线5cc8868相同。相机PLL×6、RCLK16.667MHz/SLOW、单次40ns采样、连续跨场FIFO行信用调度，以及所有现有诊断逻辑均保留。没有按图像内容自动交换Y/UV、修补像素或通过丢坏帧掩盖错误。

## 直接下载已测试程序
安装Vivado2025.1，按[接线与使用](docs/wiring_and_use.md)接线，所有开关先置0。在本目录执行：
~~~powershell
powershell -ExecutionPolicy Bypass -File .\program_lcd.ps1
~~~
脚本连接Basys3目标210183BCBF83A，下载artifacts/lcd_top_snapshot.bit及对应ltx，然后交回实体开关。只写FPGA配置RAM，断电后需要重新下载。bit的SHA256为b33cd1017aa1dbe9d4aa03037e1271d05a9e84d0ce3b92a518d018da88a551e9；本次未重新下载或改变板上程序。

## 从源码构建
~~~powershell
powershell -ExecutionPolicy Bypass -File .\build_lcd.ps1 -Snapshot -OutDir E:\FPGA_Test_Work\edge20fps_build
~~~
脚本会创建Vivado工程及VIO IP，综合、布局布线后生成并复制lcd_top_snapshot.bit/ltx到artifacts。生成的project目录可用Vivado打开。源文件、约束和IP配置均随工程提供；不需要旧实验目录中的缓存。默认构建Snapshot诊断版，与当前已测程序功能配置对应。若更换电脑，可通过-Vivado指定Vivado路径，-OutDir指定构建目录。重建可能产生不同bit字节，现有artifacts仍是原先上板验证的文件；请先备份它再自行重建覆盖。

scripts/build_pair_uart.tcl等保留缓存式历史构建入口，已将其VIO配置路径改为随工程提供的ip/lcd_vio/lcd_vio.xci；推荐使用上面的完整构建入口。build_slow_only.tcl属于历史checkpoint单变量实验，依赖当时未随仓库提供的生成缓存，不是当前重建入口。

## 实体开关
保持SW0=0、SW1=0用于真实摄像头；SW2=0显示RAW灰度，SW2=1显示高斯＋Sobel。SW15=0连拍，SW15=1让当前帧完成后暂停。SW0=1选择内部斜纹；SW1只在复位初始化期间选择相机色条。BTNC重新初始化。模式切换可能短暂清背景。SW3等其余开关保持0；SW14为错误LED页。
VIO调试助手可能接管实体开关；scripts/paired_overview_hardware.tcl physical -snapshot可交回。

## 串口诊断（可选）
~~~powershell
E:\Python\python.exe -m pip install -r requirements.txt
E:\Python\python.exe pc_diag\record_pairs.py --label unique_run --frames 600 --show
~~~
默认只打开COM10、12000000baud；代码拒绝COM15。真实RAW连拍时被动回传160×120双字节概览：左通道是实际显示的Y候选，右通道是前一个相邻字节，右侧浮雕本身属于诊断数据，并非第二幅正常图。LCD仍输出完整VGA；这不是全分辨率串口视频。仅摄像头RAW（包括相机色条）发送，EDGE/内部图不发送。有限发送缓存溢出只计数并中止诊断包，不反压核心，不增加整帧FPGA缓存。

## 验证与当前状态
- 改线后固定色条RAW/EDGE各完成500帧目标，约22.5077fps；完整图像参考CRC检查通过，EDGE参考由主机轮询覆盖。
- 实拍RAW补采600个连续有效诊断包，头/负载CRC、帧号缺口、FPGA诊断丢包均0；概览筛查未发现之前明显的Y/UV互换。抽样不能证明未导出像素全部无错。前一轮PC在316张时PermissionError终止，已单独记录。
- 实拍EDGE完成500帧目标，约22.5077fps；像素数和写屏前后CRC一致。它不能单独证明实拍内容或面板扫描瞬间无错。
- 用户在改线后确认20fps验收基本通过。均匀横细纹已由用户确认为照明频闪，本轮不处理。强光/快速运动时的斜向刷新区域尚未单独定位；当前不做TE扫描同步或双缓冲换页，不能保证无刷新撕裂。滚动快门也可能产生运动形变。
- 用户修改了地线和RST/SIOC/SIOD上拉，并报告此前3V3/GND接反；实际总线长、寄生参数及器件健康没有仪器测量，不标成已验证10cm硬件条件。

[当前验证记录](reports/evidence/rewire_20fps_20261031.md)、[结构化结果](reports/evidence/rewire_20fps_20261031.json)、[实现报告](reports/evidence/implementation/timing.rpt)、[整理清单](docs/package_manifest.json)随工程保留。docs中其他诊断记录按文件名和日期视为历史；其失败结论不是本次改线后的最新结果。大批实拍原始帧、wire.bin、Vivado缓存未上传，原实验目录保留。

## 仿真入口
安装requirements.txt后可运行：
~~~powershell
E:\Python\python.exe scripts\run_lcd_tests.py core_unique tb_video_path --vga
E:\Python\python.exe scripts\test_video_capture.py camera_unique --vga
E:\Python\python.exe scripts\test_uart_pair.py uart_unique --vga
~~~
标签必须唯一，结果输出到本工程reports的忽略目录。仿真、布局布线、板上CRC和用户视觉观察是不同证据层级。后续按需要再做代码收敛；本次不新增算法、自动阈值或消撕裂机制。
