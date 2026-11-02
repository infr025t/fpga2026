# 算法原理与当前实现边界

本页按当前RTL与PC参考说明每一级计算的输入、整数规则、坐标与硬件实现。视频支路为Gaussian3 + Sobel3；旧引导滤波方案已退出当前工程。训练与权重见[模型与训练](model_and_training.md)，实现数据见[当前验证](current_validation.md)。

## 两条处理路径必须分开描述

视频 RAW/EDGE 路径处理 640×480 灰度像素流。EDGE 使用行缓存生成邻域窗口，逐有效像素计算 Gaussian3 与 Sobel3；它不需要在 FPGA 中先保存整个 VGA 图像再滤波。识别路径直接旁接原始灰度源，从一帧中采样得到 160×120 小图，保存完整小图之后串行执行定位、分割、逐字符归一化和 CNN。因此“流式视频前端”成立，“整套 OCR 无帧缓存、每像素到达立即给识别答案”不成立。OCR 不读取显示用 Sobel 二值边缘，而是读取自己的原灰度小图。连接证据：[lcd_top.sv](../../project/rtl/top/lcd_top.sv)、[plate_recognition_subsystem.sv](../../project/rtl/recognition/plate_recognition_subsystem.sv)。

SW4=1 请求识别并覆盖 SW3 的 EDGE 请求；否则 SW3=1 为 EDGE、SW3=0 为 RAW。识别模式以 RAW 背景显示，识别状态叠字来自独立结果事件。代码：[display_mode_control.sv](../../project/rtl/top/display_mode_control.sv)。模式开关不改变冻结 CNN 权重或数学定义。

## 视频：Gaussian3、Sobel3 与实际裁边

### 局部窗口

[row_window3.sv](../../project/rtl/video/row_window3.sv) 的三个独立单口同步 RAM bank 按行轮换：当前行写一个 bank，其余两个 bank 读相同 x；当前像素旁路，带着坐标/帧号/valid 对齐输出三行。水平相邻两列保存在寄存器中。输入空拍不推进像素窗口，但 valid 流水仍前移；rst/abort 清有效状态，RAM 内容不整块清零，起始缺失行被屏蔽。它依赖按顺序到达的坐标，不是任意坐标随机访问滤波器。

Gaussian 权重矩阵为 `[1,2,1; 2,4,2; 1,2,1]`，和为 16。输出 `G=(Σw×p+8)>>4`，同时把窗口中心的原灰度像素传递给后级 `out_raw`。坐标使用窗口右下点减 1，只有行/列均已累计三点时有效。见 [gaussian3.sv](../../project/rtl/video/gaussian3.sv)。

Sobel 在 Gaussian 结果上计算右列加权和减左列加权和为 Gx、下行加权和减上行加权和为 Gy；幅值使用 `|Gx|+|Gy|`，不是平方根欧氏范数。单轴在 [-1020,1020]，幅值上界 2040；满足 `magnitude >= threshold` 输出 255，否则 0。当前适配器将 threshold 固定为 128；`edge_core` 在输入 SOF 锁存阈值/视图。见 [sobel3.sv](../../project/rtl/video/sobel3.sv)、[video_core_adapter.sv](../../project/rtl/video/video_core_adapter.sv)。

### 为什么两级 3×3 仍然裁每边 5 像素

不能只按卷积有效范围估计输出尺寸。当前 RTL 明确保留既有裁边接口：

1. Gaussian3 的有效中心理论覆盖 x=1..W-2、y=1..H-2。
2. `edge_core` 的 `pv` **额外**仅接受 `4<=ax<=W-5`、`4<=ay<=H-5`；送入 Sobel 的区域为 `(W-8)×(H-8)`。这一步主动放弃了一部分本可用 Gaussian 输出。见 [edge_core.sv](../../project/rtl/video/edge_core.sv)。
3. Sobel 实例参数为 `(W-8,H-8,4)`，先减 OFFSET=4 建立局部坐标，再由 3×3 窗口丢一圈，因此最终全局中心是 x=5..W-6、y=5..H-6。见 [edge_core.sv](../../project/rtl/video/edge_core.sv)、[sobel3.sv](../../project/rtl/video/sobel3.sv)。
4. W=640、H=480 时输出 x=5..634、y=5..474，数量 `(640-10)×(480-10)=630×470=296100`。适配器坐标减 5，变成 x=0..629、y=0..469；LCD sink 同样按 W-10/H-10 计数，显示窗保留每边 5 像素空边。见 [video_core_adapter.sv](../../project/rtl/video/video_core_adapter.sv)、[video_lcd_sink.sv](../../project/rtl/video/video_lcd_sink.sv)。

因此这里的 5 像素是**显式门控及系统接口合同**，不是 Gaussian3+Sobel3 数学有效支撑必然需要的半径；两级 3×3 合成支撑为 5×5，只需数学半径 2。当前源码注释写明保留 established 5px crop，但没有充分证据说明最初历史设计为何选 5，本文不补造起因。本轮不能为“纠正尺寸”直接删门控，否则 SOF/EOL/EOF、坐标、显示窗口、像素计数及参考 CRC 都需同步重验。

RAW 模式通过适配器旁路，保留 640×480=307200 像素；不要将 EDGE 的 `out_raw` 当作全 VGA RAW，它是与边缘中心对齐的裁边灰度副本。见 [video_core_adapter.sv](../../project/rtl/video/video_core_adapter.sv)。

## OCR 采样与坐标合同

自主控制器检查输入必须按 x=0..639、y=0..479 顺序组成 307200 个源像素。只在 `x mod 4=3` 且 `y mod 4=0` 时保存一个像素，得到 19200 个样本。小图坐标 (u,v) 对应原流 (4u+3,4v)，这是真正的隔点采样，不是 4×4 均值缩小；没有额外抗混叠滤波。见 [plate_auto_controller.sv](../../project/rtl/recognition/plate_auto_controller.sv)。

ROI 用 `(x0,y0,x1,y1)` 右下不包含端点，字符框用 `(x,y,w,h)`，所有 OCR 坐标属于 160×120 小图，不属于 630×470 显示边缘图。人工协议支持 flags bit0 旋转180°、bit1 灰度反相，坐标定义在变换后的逻辑图；v1.1 自主子系统按接纳帧时的SW5生成 flags：暗字为0，白字为2，不旋转；原图RAM与定位输入保持原灰度。见 [plate_auto_controller.sv](../../project/rtl/recognition/plate_auto_controller.sv)、[segment_ref.py](../../project/pc/segment_ref.py)、[norm_ref.py](../../project/pc/norm_ref.py)。

## 图像几何定位：原灰度上的亮度与单牌面约束

RTL [plate_region_locator.sv](../../project/rtl/recognition/plate_region_locator.sv) 与参考 [plate_locator.py](../../project/pc/plate_locator.py) 均不读取 CNN 类别或目标答案。

1. 扫描整幅小图求灰度最小/最大值；差小于 32 时无定位。
2. 阈值为 floor((min+max)/2)，像素严格大于阈值为亮点。每行亮点数≥40 才属于候选行带。
3. 以连续合格行组成带，要求不接触上下图像边界，带高 12..60。
4. 取带内亮点最多的行，在此行寻找最长亮跨度，中间最多容忍两个暗点；并列采用较早/较左的候选。
5. 跨度不得触及左右图像边界，宽≥64 且宽≥2×带高，以带内亮点总数最大者作为结果。
6. 输出 `(left,max(0,top-3),right-1,end-1)`；这里 right/end 是检测得到的不包含边界，输出的 x1/y1 仍按后续 ROI 不包含规则解释。也就是说代码实际对右/下边界内缩一格，不能自行改写成返回 `(left,top-3,right,end)`。

这些规则继续约束原灰度中的亮区域及单牌面几何；白字选择只改变后续字符处理，不自动扩展定位范围。场景条件集中说明在[白字支持](white_character_support.md)。定位失败时前端正常结束且零框，并非自动选择任意全图备用 ROI。定位与分割通过 `plate_segment_frontend` 串行共享原小图读口；人工模式跳过定位、采用上传 ROI，并关闭自主前缀/粘连策略。见 [plate_segment_frontend.sv](../../project/rtl/recognition/plate_segment_frontend.sv)。

## 局部阈值、连通域与字符组

参考定义为 [segment_ref.py](../../project/pc/segment_ref.py) 与 [segment_ref.py](../../project/pc/segment_ref.py)，RTL 为 [char_segmenter.sv](../../project/rtl/recognition/char_segmenter.sv)。这是保存小图上的多遍处理，不是显示路径的 Gaussian/Sobel。读取像素先应用flags bit1：暗字令 `I=raw`，白字令 `I=255-raw`；后续局部阈值与连通域规则完全相同。

- 对 ROI 内每像素做 15×15 局部均值，邻域越过 ROI 时复制 ROI 边缘值。225 点求和 S，均值 `M=floor((S+112)/225)`；当前像素满足 `I<=M-12` 为暗字前景。整数 RTL逐 tap 读小图，并做除法，不能称作每时钟一个阈值输出的15行流水。
- 行优先找种子，8 邻域 BFS 洪泛。入队即清 mask，防止重复入队；每个连通域保存外接矩形和前景面积。队列按连通域复用，最多 19200 点。
- 令 ROI 高 H，字符高度下限 `max(5,round_even(H/10))`，上限 `max(8,round_even(85H/100))`；round_even 是半值取偶。普通候选需高度在范围内、w≥2、5w≤7h、前景面积≥h。
- 以每个候选作为组基准，比较两倍垂直中心距离：`10×|(2y+h)-(2y0+h0)| < 9×max(h,h0)`，且 `2h0>h`、`h0<2h`。组得分为成员高度之和，取严格更高分的组；并列保持先前组。
- 将最佳组高度排序得到两倍中位数 median2，保留 `40h>=13×median2` 的框，再按 x 升序输出。候选上限 64，溢出状态 3；输出可能为零，不强迫固定 7 字符。

### 前缀与粘连修正

前缀规则排除中心落在当前 ROI 左侧 1/8 内的候选；全局形式为 `2x+w >= 2×(x0+floor(ROI_width/8))` 才保留。它利用“最左位为汉字”的版式假设，既不识别汉字，也不检查 CNN 是否像中文；版式不满足时可能删除有效字符。见 [char_segmenter.sv](../../project/rtl/recognition/char_segmenter.sv)、[segment_ref.py](../../project/pc/segment_ref.py)。

touching split 仅尝试宽连通域 `h<=w<=2h`，高度/面积仍需合格。在中间三分之一区域选择相邻两列前景数之和最小的切点，并要求谷值≤floor(h/8)。按切点将原 BFS 坐标分成左右子域；两个子域均须 w≥2、高度合格、4×子高≥3×父高、5×子宽≤4×父高、面积≥子高且前缀规则通过，才替换父框。否则退回普通候选判定。每个父域最多拆一次，无递归猜字符数、无 CNN 回馈或答案导向试分割。RTL复用当前洪泛队列，不增加第二幅二值图。见 [segment_ref.py](../../project/pc/segment_ref.py)、[char_segmenter.sv](../../project/rtl/recognition/char_segmenter.sv)。

## 归一化：灰度字符到 32×24 uint8

参考 [norm_ref.py](../../project/pc/norm_ref.py)；硬件 [char_normalizer.sv](../../project/rtl/recognition/char_normalizer.sv)。归一化使用与分割同一帧锁存的flags，先将白字读取为 `255-raw` 再执行下列统计，因此CNN仍接收亮笔画、暗背景的统一表示。仅切换分割而不切换归一化会使两级对字符前景的理解不一致。

1. 字符框四周最多扩 2 像素，并裁到 ROI，不越界访问原图。
2. 在扩展框灰度统计直方图；使用线性百分位 P3 与 P85。秩 `(N-1)×p/100` 的整数部分/余数定义插值，保存100倍值，避免浮点口径差。
3. `high=high100//100`；`den=max(16,(high100-low100)//100)`。输出对比灰度为 `clip(((high-I)×255+den//2)//den,0,255)`，亮背景被映成低值，暗字符映成高值。
4. 保持宽高比放入 22×30 的内部区域，缩放后尺寸使用 round_even，至少 1 像素；在 24×32 全零画布上居中。最终输出按行优先共 768 字节。
5. 面积重采样对放大、缩小都按像素区域交叠加权；二维总和除以源宽×源高，最后一次 half-up 舍入。不是最近邻、双线性或调用库的近似浮点 AREA。尺寸舍入、百分位插值和像素舍入应分别描述，不能统一写“round”。

硬件按状态机反复读取扩展框、建立256项直方图/LUT、调用整数除法器和输出像素。输入框越界/空框报错；保存的源图不被归一化原地覆盖。见 [char_normalizer.sv](../../project/rtl/recognition/char_normalizer.sv)、[norm_ref.py](../../project/pc/norm_ref.py)。

## CNN：量化算法与串行排程

网络为 Conv(1→8,3×3)+ReLU+MaxPool2、Conv(8→16,3×3)+ReLU+MaxPool2、FC(768→36)。完整量化尺度、模型来源、MAC数见 [model_and_training.md](model_and_training.md)。当前 RTL 在每个池化输出位置依次计算四个卷积子像素，量化后更新 pool_max，只把池化结果存回 RAM；并不保存两幅完整未池化激活图。见 [cnn_core.sv](../../project/rtl/recognition/cnn_core.sv)。

每个 tap 经 TAP_READ→TAP_MUL→TAP_ACC，使用同步权重 ROM、一个17位有符号乘积寄存器和32位累加；还需偏置、量化、池化存储及层切换周期。第1层池化 8×16×12=1536 字节放 ram_b，第2层池化 16×8×6=768 字节放 ram_a，之后 FC。ram_a/ram_b 各声明2048字节，共4096字节；元数据中12288字节特征预算是软件模型预算，不是本 RTL 工作 RAM 的实际数组容量。见 [cnn_core.sv](../../project/rtl/recognition/cnn_core.sv)。

输出36个 signed int32 分数，由自主控制器校验类别范围/重复/完整集合，并以有符号 argmax 选择；同分选择较小类别编号。归一化、CNN对多个字符串行执行，未采用跨字符双流水并发。没有置信度拒识阈值、字典纠错或语法纠错；有结果不保证字符真值正确。见 [plate_auto_controller.sv](../../project/rtl/recognition/plate_auto_controller.sv)。

## 可陈述与不可外推的吞吐边界

视频滤波 valid 数据通路、帧缓存 OCR、UART 发布以及 LCD 绘制各有不同节拍。边缘算子可接受连续有效像素只说明接口计算排程；整机源帧率受相机读取和显示接纳限制。OCR 的单份小图在当前识别完成前不接收下一识别帧，忙时只增加 skipped_frames；UART 无 ready 回传，拥塞可丢观察数据。保存数据中约5.63 OCR fps、约22.51源帧起始fps属于历史基线，不能直接写成当前新 BIT 性能。各数值及测量口径引用 [resource_and_timing.md](resource_and_timing.md)，本页不增加实测数据。
