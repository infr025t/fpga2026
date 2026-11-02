# v1.1 白字支持：原灰度定位，按字符极性分割与归一化

v1.1 用SW5为自主OCR增加白字选择。蓝底白字的字符先按现有反相功能转换成暗字，再进入原分割与归一化流程；相机采集、小图RAM、几何定位和LCD灰度背景仍保持原值，CNN权重保持不变。

## 现象与同图证据

实际蓝底白字采集保存于[blue_before](../../evidence/blue_polarity/blue_before/summary.json)，帧号为22673、22676、22679、22682、22685。原图人工目视读为“晋A·L67L8”，英数字部分为AL67L8；用户当时确认已对准，但未单独提供号码真值，原采集未设置truth评分字段。中文省份字和中点不属于36类CNN输出。

| 同一批五帧的处理方式 | 定位结果 | 识别输出 | 证据类型 |
|---|---|---|---|
| 原暗字链路 | 五帧均为 `[21,34,156,81)` | `1AW`、`1AW`、`01`、`0D`、`01` | 旧BIT实拍，并与旧整数参考一致 |
| 整幅图先反相，再执行原定位 | 五帧均无ROI | 五帧空串 | 同图软件对照 |
| 原灰度定位，分割与归一化flags=2 | 五帧均为原ROI，每帧六个字符框 | 五帧均为 `AL67L8` | 同图软件重推理 |

[整体反相对照](../../evidence/blue_polarity/blue_probe.json)和[局部处理反相对照](../../evidence/blue_polarity/blue_seg_invert_probe.json)说明：本场景的原定位已找到区域，主要错误出在按暗字提取白字。把反相放到采集前端会改变定位器看到的亮度结构；只在字符处理阶段复用反相功能，可保留这批图像已有的定位结果。五帧属于同一牌面的重复采集。

## 最小实现

生产RTL只修改两个文件：[lcd_top.sv](../../project/rtl/top/lcd_top.sv)将同步后的SW5连接到 `white_characters`；[plate_recognition_subsystem.sv](../../project/rtl/recognition/plate_recognition_subsystem.sv)负责帧级锁存、flags分发与切换中止。其余38个RTL文件、模型和约束保持不变，见[源变更审计](../../evidence/blue_polarity/source_change_audit.json)。

识别子系统在允许接纳源帧时锁存SW5，生成 `a_flags={active_white_characters,1'b0}`。SW5=0时flags=0；SW5=1时flags=2，沿用既有bit1反相功能。分割器读取 `I=255-raw` 后执行原局部阈值、连通域与候选规则；归一化以同一反相灰度执行百分位、对比度和面积重采样，使CNN继续接收亮笔画、暗背景的32×24字符。无需增加另一幅图像RAM或修改CNN权重，实际资源增量由新实现报告确定。

定位器始终读取原灰度，不使用字符极性改写亮度搜索。原始小图不被原地覆盖，RAW/EDGE和LCD灰度背景也不反相。自主OCR中改变SW5会沿用模式切换机制复位旧任务，清除待显示的旧文字与ROI；显示在下一接纳的视频帧边界提交，暂停时屏幕仍冻结。下一次接纳的完整源帧使用新选择，不在同一任务中混用两种极性。

人工模式使用上传的 `m_flags`，不由SW5覆写；在RAW、EDGE或人工模式下拨动SW5不触发自主极性任务切换。SW4/SW3的三模式优先级保持原定义。

## 使用方式

| 目标 | 实体开关 | VIO脚本动作 |
|---|---|---|
| RAW | SW4=0，SW3=0 | `raw` |
| EDGE | SW4=0，SW3=1 | `edge` |
| 暗字OCR | SW4=1，SW5=0 | `auto`，virtual_sw=0x0010 |
| 白字OCR | SW4=1，SW5=1 | `auto_white`，virtual_sw=0x0030 |

正常相机识别保持SW0、SW1、SW12、SW13、SW14、SW15为0；使用实体开关前解除VIO覆盖。SW3在SW4=1时不再选择EDGE。切换SW5无需BTNC。接线、串口和RAM下载步骤见[接口与操作](interfaces_and_operation.md)。

## 原始数据与PC参考

AIF1继续发送原始160×120灰度字节，raw_crc也对应这些原值；flags bit1仅声明分割和归一化的反相解释。协议格式不变，旧flags=0数据语义不变。`auto_verify.py`对自主定位合同允许flags为0或2，先在原图上定位，再用同一flags重算分割与归一化。PC工具仍只接收、落盘和核验，串口不对计算核心施加反压。

## 已完成验证

[仿真汇总](../../evidence/blue_polarity/simulation_summary.json)记录以下结果：

| 检查 | 结果 |
|---|---|
| PC回归 | 61项测试通过 |
| 极性切换控制 | 半帧采集中止、原始字节保留、flags=2锁存、取消后撤框通过 |
| 白字完整链 | 六字符输出AL67L8；4,608个归一化像素、216个有符号分数与整数参考零差异；空白帧撤框通过 |
| 原暗字完整链回归 | 七字符输出BD12345；5,376个归一化像素、252个有符号分数与整数参考零差异 |

白字整链使用真实工作模块，保存的[仿真wire回放](../../evidence/blue_polarity/simulations/sim_white_characters/replay/summary.json)包括识别帧与空白帧。新构建已完成布局布线和RAM下载：100 MHz下WNS +0.175 ns、WHS +0.017 ns。实机当前蓝牌20次均输出AL67L8，120字符的92,160像素和4,320分数与参考零差异，见[板测](../../evidence/blue_polarity/board_white_20/summary.json)与[当前验证](current_validation.md)。原始字节、ROI和flags的完整协议也已在这20组数据中核验。用户本轮不方便查看，屏幕目视确认不计为已完成。

## 适用条件

SW5解决字符亮暗极性，不改变原定位器的亮度与几何条件。牌面应完整入镜、近水平、大小满足原ROI约束，且原灰度中存在定位器可选出的亮区域。蓝色在灰度图中的亮度受照明与曝光影响，因此本次五帧成功不能推广为任意暗蓝底、任意背景或任意位置均可定位。

同一实拍帧另做[合成对比度缩减](../../evidence/blue_polarity/contrast_sensitivity.json)：对比度比例1、3/4、1/2时均输出AL67L8，1/4时退化为三个候选、输出IL8。实验未调阈值或增加算子，复用既有归一化对比度拉伸；这些合成输入不属于新的真实曝光样本。

字符和牌底接近同亮度时，反相只改变明暗方向，不能恢复已缺失的笔画对比度，应先改善照明、曝光或摆放。前缀、边框候选和粘连规则仍使用原实现，后续以独立牌号与位置数据评价。相关既有问题保留在[验证数据](validation_data.md)与[异常台账](anomaly_register.md)。
