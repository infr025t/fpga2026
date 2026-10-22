# ROI单目标统计与FPG1 v2协议

本轮接口约定（2026-10-19）。所有多字节字段小端；坐标是原始传感器坐标。图像仍裁去一圈边界，因此PC显示坐标需要减1。ROI和包围框的最大坐标均包含端点。

## 算法与配置

流式读取原始Y像素，在ROI内统计符合亮度阈值的全部像素：暗目标 `Y <= target_threshold`，亮目标 `Y >= target_threshold`。这是受控背景下的单目标阈值统计，不做连通域选择；多个目标会合并统计。

每帧开始锁存ROI、阈值、极性、面积上下限。有效配置要求 `1 <= roi_x_min <= roi_x_max <= W-2`、Y同理，且 `1 <= min_area <= max_area <= (W-2)*(H-2)`。无效配置不统计像素，输出配置无效、面积/累加/框均0。

匹配像素的原始面积、Sx/Sy与框保留；`target_valid = config_valid && area > 0 && min_area <= area <= max_area`。无匹配像素时面积/累加/框均0；面积过滤失败时目标无效，PC不显示框或目标中心。中心由PC计算 `Sx//area, Sy//area`，FPGA不增加除法器。

顶层SW2=0保持FPG1 v1；SW2=1启用定位并发送v2。SW3=0暗目标、1亮目标；SW9:8的00/01/10/11对应亮度阈值96/64/128/160。SW1、SW7:4继续控制图像灰度/Sobel和Sobel阈值。以上开关在帧间锁存。

默认ROI是裁剪后整个有效图像（原坐标1..W-2、1..H-2），默认最小面积16，最大面积为有效图像面积的一半。ROI和面积通过顶层参数配置。定位测试图使用暗矩形/亮背景，亮目标模式反转；SW2=0的旧测试图保持原样。

## 包结构

v1保持32字节头、Wout*Hout字节图像、2字节CRC。v2为72字节头、相同8位图像、2字节CRC。两者magic均为ASCII `FPG1`，字节4的version分别为1/2；原32字节基础头字段与亮背景统计不变。CRC-16/CCITT-FALSE仍覆盖 `header[4:] + pixels`，小端发送。

| 字节偏移 | 字段 | 类型 |
|---|---|---|
| 0..31 | 原基础头，version=2 | 原格式 `<4sBBHHHIIIII` |
| 32 | flags：bit0目标有效、bit1暗目标、bit2配置有效；其余0 | u8 |
| 33 | 目标亮度阈值 | u8 |
| 34,36,38,40 | roi_x_min, roi_y_min, roi_x_max, roi_y_max | 4×u16 |
| 42,44,46,48 | bbox_x_min, bbox_y_min, bbox_x_max, bbox_y_max | 4×u16 |
| 50,54,58 | target_area, target_sum_x, target_sum_y | 3×u32 |
| 62,66 | min_area, max_area | 2×u32 |
| 70..71 | reserved，必须0 | u16 |
| 72.. | 图像、CRC | 原格式 |

40字节扩展头Python格式：`<BBHHHHHHHHIIIIIH`。接收器兼容两版本，并检查扩展字段与有效性/面积/ROI/包围框的自洽性。v2在JSON中增加 `target` 对象（config_valid、valid、dark、threshold、roi、area、sum_x、sum_y、min_area、max_area、bbox、centroid_x、centroid_y）；无有效目标时bbox与目标中心为null。旧的顶层centroid仍是亮背景统计，不能代替目标中心。

## RTL接口

新增 `target_stats #(W,H)`，端口用具名连接：

```text
input clk, rst, frame_start, in_valid; input [7:0] in_pixel;
input target_dark; input [7:0] target_threshold;
input [15:0] roi_x_min, roi_y_min, roi_x_max, roi_y_max;
input [31:0] min_area, max_area;
output done, config_valid, target_valid;
output [31:0] target_area, target_sum_x, target_sum_y;
output [15:0] bbox_x_min, bbox_y_min, bbox_x_max, bbox_y_max;
```

该模块与image_core并行接收同一原始像素流，不增加行缓冲或帧缓存。只处理W×H个像素，额外像素忽略；新frame_start中止前一帧并重置结果。done是最后输入像素之后的单周期脉冲，结果在done时完整并保持至下一帧。target_valid可以随统计组合计算，但仅在done后使用。

`frame_sender` 保留旧端口顺序，在末尾增加具名输入；新增参数 `TARGET_PROTOCOL=0`，0时无条件v1，1时由target_enable选择v1/v2。新增输入：

```text
target_enable, target_valid, target_dark, config_valid;
[7:0] target_threshold;
[15:0] roi_x_min, roi_y_min, roi_x_max, roi_y_max;
[15:0] bbox_x_min, bbox_y_min, bbox_x_max, bbox_y_max;
[31:0] target_area, target_sum_x, target_sum_y, min_area, max_area;
```

发送开始时锁存全部头字段及头长度，发送期间输入变化不能影响当前包。顶层启用TARGET_PROTOCOL=1；旧独立发送器测试保持默认v1。新增tb_target_transport写 `target_wire.bin`，包含至少一帧有效目标和一帧无目标，供PC交叉验证。
