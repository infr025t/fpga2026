# 高速测试诊断证据
基线main5cc8868，实验均在本目录，核心4文件保持原hash。
1. x6实际周期约4442922个100MHz时钟，即22.5077fps，HREF7110..7112拍。RCLK16.667MHz，LCD每像素120ns。
2. 奇数位误取UV：完整CRC17e5bee9。真实原尺度640x16 strip偶数位Y重复480行CRC6df0b9b5，恰为历史正确RAW；修改Y_BYTE=0并取RRST预取byte0后，小尺寸/VGA环绕暂停模型均通过。
3. 去除gap后必须等完整源帧结束再下一start，不能只等裁边EDGE EOF。红绿回归已通过。
4. y_even_500在第85帧失败，CRCc90d2573，等价于前147456像素取上次FIFO轮次内容、其余正确。
5. locator_01第105帧错误98304像素，首index0读45而非206，末index98303。其CRC00d43d31可精确重建为前98304像素行相位+512，其余正确。+512等价FIFO容量196608像素的前一轮内容(-196608 mod640=512)。两轮错误区域都在下一物理读地址回绕处结束。
因此已确认是旧FIFO数据区间，尚未定位到具体电气/刷新/控制原因；不是算法差异或全帧坐标错位。SLEW FAST->SLOW保持频率/布局/调度不变的单变量对照正在运行。
6. Native完整色条Y用于软件模型，Gaussian/Sobel T128完整EDGE参考CRC2c1f5efc。只用于诊断核对，不更改处理输出。

## 最终边界
SLOW与FAST用同一post_route checkpoint，只修改cam_rclk的SLEW；RAW连续1500帧全参考通过，频率仍22.5077fps。随后10次暂停恢复计划在epoch1失败：前52395像素正确，index52395起突然相位错误，firstgot128/expected23，故不能认定稳定解决。
SLOW EDGE前375帧全参考2c1f5efc正确，之后一次host REFERENCE_ERROR停止。该次旧脚本没有记录停前badCRC，不能补造故障字节或宣称捕获了该帧的完整定位；最终inspection对应暂停排空后的最后帧，而非坏帧。脚本现已补充停前上下文保存，修改后未再次上板重测。
最终布局setup+.410ns、hold+.023ns，3221LUT/11BRAM36eq/6DSP（包括诊断）。候选hash见reports/final_status.json。数值核心4文件hash仍与main相等。
用户确认当前仍约20cm接线，接受它作为偶发异常的可能因素；先保留候选并停止软件重复测试，待缩线后同参数复验。尚未证实唯一根因，未宣告正式20fps稳定完成。
