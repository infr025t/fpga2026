# 冻结模型、训练与数据来源

## 版本身份

当前发布使用已验证的冻结模型，模型权重、CNN算术、归一化及前端阈值保持一致。板端模型 `kind=gray`，输入 `[1,32,24]`，输出类顺序为 `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ`。包括 I/O 共 36 类，无中文省份类；前缀排除不等于中文识别。

- [板端 model.bin](../../project/model/model.bin)：29128 字节，SHA256 `179d6d9b9a4e2229c152770152fe6c8d71ff924af5d9da06132debd730cf4645`。
- [结构及量化元数据](../../project/model/model.json)、[训练结果](../../project/model/training_result.json)。上述 binary 与 `plate_cnn32_pc_v2_20261101/models/gray/model.bin` 哈希相同。
- [训练源码](../../evidence/history/plate_cnn32_pc_v2_20261101/train_cnn.py)、[数据清单](../../evidence/history/plate_cnn32_pc_v2_20261101/data/manifest.json)、[整数参考](../../evidence/history/plate_cnn32_pc_v2_20261101/integer_cnn.py)。完整文件哈希见 [data_sources.json](../../evidence/data_sources.json)。

## CNN 结构与计算量

形状按 channel × height × width。卷积均为 3×3、步长 1、四周补 1 个零；池化为 2×2 max pooling，步长 2。

| 层 | 输出形状 | 权重数 | 偏置数 | 每字符 MAC |
|---|---|---:|---:|---:|
| 灰度输入 | 1×32×24 | 0 | 0 | 0 |
| c1 + ReLU / uint8 重新量化 | 8×32×24 | 8×1×3×3=72 | 8 | 55296 |
| pool1 | 8×16×12 | 0 | 0 | 0 |
| c2 + ReLU / uint8 重新量化 | 16×16×12 | 16×8×3×3=1152 | 16 | 221184 |
| pool2 | 16×8×6 | 0 | 0 | 0 |
| flatten + fc | 36 | 36×768=27648 | 36 | 27648 |
| 合计 | 36 个 signed int32 logits | 28872 | 60 | 304128 |

MAC 是一次乘加的算法计数，不是 FPGA 时钟周期；边界补零亦按完整卷积算式计入。分数用于有符号 argmax，不要求 softmax 概率。每字符实际核心时间由硬件 `core_cycles` 测量，不能拿 MAC 数直接作为周期数。

## 量化合同

浮点输入为像素值除以 256。权重采用每层二次幂步长，`w_q=clip(rint(w/2^e_w),-127,127)`；偏置单位为输入尺度与权重尺度之积，保存为 int32。权重/偏置导出时 `np.rint` 与激活运行时的半值处理不是同一操作。

整数累加为 `a = bias_q + Σ(input_q × weight_q)`。卷积输出执行 `u = clip((a + 2^(s-1)) >> s, 0, 255)`，即右移前加半量阶、随后 ReLU 与 uint8 饱和；本模型两个 shift 都为正。max pooling 对已量化 uint8 值取最大。fc 输出不再压成 uint8。

| 层 | 输入 exponent | 权重 exponent | 输出 exponent | shift | 元数据保守累加绝对界 |
|---|---:|---:|---:|---:|---:|
| c1 | -8 | -6 | -6 | 8 | 88678 |
| c2 | -6 | -7 | -3 | 10 | 648134 |
| fc | -3 | -7 | int32 logits，尺度 2^-10 | 无 | 2423601 |

界按 `max_o(|bias[o]| + 255 × Σ|weight[o]|)` 计算，用于检查最坏输入范围，不是实测最大激活或溢出统计。训练代码要求小于 2^30；本模型三个界均满足。

模型布局：8 字节 `PCNN3201` 头，8 字节两个 little-endian int32 shift；随后 c1w/c1b/c2w/c2b/fcw/fcb。偏移分别为 16/88/120/1272/1336/28984。权重 int8 共 28872 字节，偏置 int32 共 240 字节，加头和 shift 合计 29128 字节。

`feature_pingpong_bytes=12288`、`score_bytes=144`、`point_accumulators_bytes=64`，软件排程工作区预算为 12496 字节。这是数据结构预算，不是整机综合 BRAM 用量；实际设计还包含图像、协议、调试及视频相关存储。

## 数据如何生成及划分

[通用字体生成器](../../evidence/history/plate_cnn32_pc_v2_20261101/data.py) 从 Windows 字体渲染单字符，并增强尺寸、宽高比、旋转、剪切、模糊、亮度梯度、噪声和归一化后 ±1 像素平移。实际 v2 数据脚本 [data_plate.py](../../evidence/history/plate_cnn32_pc_v2_20261101/data_plate.py) 从旧目录 `plate_cnn32_pc_20261101/data` 读取保存的通用数据，再拼接车牌字模增强样本；不能把 v2 中保存的 `data.py` 等同于当时重新生成全部字体数据的执行证据。

| 集合文件，位于 v2/data | 数量 | 生成单位/来源 | seed | 类别覆盖 |
|---|---:|---|---:|---|
| 通用 train，拼入 train.npz | 20736 | 24 字体×36 类×24 次 | 77331 | 36 |
| validation.npz | 2160 | 6 字体×36 类×10 次 | 99231 | 36 |
| test.npz | 2880 | 8 字体×36 类×10 次 | 48331 | 36 |
| plate_train.npz | 11776 | 92 个非 green 字模×128 次 | 3157 | 34，不含 I/O |
| plate_validation.npz | 1840 | 同 92 个非 green 字模×20 次 | 7742 | 34，不含 I/O |
| plate_test.npz | 1360 | 34 个 green 字模×40 次 | 9917 | 34，不含 I/O |
| train.npz 最终合并 | 32512 | 20736+11776 | 各自生成 seed | 36 |

保存 NPZ 均有 `gray`、`edge_norm` 和 `labels`；图像数组为 N×32×24 uint8，labels 为 int64。本次读取实际文件确认数量与形状，未重新生成或重训。

通用训练字体来自 Arial/Arial Narrow、Calibri、Consolas、Bahnschrift、Tahoma、Trebuchet、Impact 及所列字体变体；验证为 Segoe UI/ Verdana 的 6 个文件；测试为 Courier New/Times New Roman 的 8 个文件。确切文件名与旧 NPZ 哈希在 manifest 内。字体文件二进制本身没有纳入该历史 manifest；当前操作系统字体可能变化，严格字节级重生成需补存当时字体及软件环境。

车牌字模来自本地 `vendor/plate_generator/font_model`，训练包含 140、220、220_down、220_up 非 green 文件，测试为 green 文件。保留 [MIT LICENSE](../../evidence/history/plate_cnn32_pc_v2_20261101/vendor/plate_generator/LICENSE)（Copyright 2020 leijd）及 [vendor README](../../evidence/history/plate_cnn32_pc_v2_20261101/vendor/plate_generator/README.md)。这是本地快照来源，不声称已核验上游当前版本或取得固定上游 commit。126 个实际用到的字模均有 SHA256。

车牌增强包括轻微腐蚀/膨胀、13..43 像素高度、宽高比例扰动、±9°旋转、剪切与平移、对比度、模糊、噪声。`plate_train` 与 `plate_validation` 的 92 个源字模完全相同，仅随机增强 seed 和次数不同，所以验证集不是独立字模来源；`plate_test` 的 green 文件与训练文件不相交，但仍属于同一供应字模集合的合成字符测试。文件不相交不自动证明字形风格独立。

## 训练与模型选择

历史训练脚本依次训练 gray、edge_norm 两种输入；本工程仅使用已冻结 gray 结果。24 个 epoch；随机 seed 604，DataLoader shuffle generator seed 312，batch=128，AdamW learning rate=0.002、weight decay=0.001，CosineAnnealingLR 到 eta_min=0.0002，cross entropy。代码开启 deterministic algorithms，CPU 线程 6、interop 2；结果记录 torch `2.15.0+cpu`。这些是代码/记录中的配置，不是跨版本完全重现的保证。

每轮用 `(generic_validation_accuracy + plate_validation_accuracy)/2` 等权选择，**不是**把 2160+1840 个样本直接合并后按样本数加权。gray 最佳 epoch=20，选择分数 0.9917673107890499。激活量化仅从合并训练集合无放回抽取 2048 个样本，seed=182；两个浮点最大激活为 3.5081722736358643 和 16.755889892578125。

训练源码不读取真实相机目录，记录明确 real camera evaluation 不参与 epoch 选择。这支持“此训练流程未用实拍数据选轮”；不能据此宣称后续前端设计、模型方案选择或整个系统研究流程均未接触这些实拍场景。

## 保存的分类指标

来源均为历史 `training_result.json`。以下分母是合成单字符，不能直接写为整牌识别率。括号为由比例×样本数还原的正确数量；浮点/整数预测一致率只比较预测类，不比较 logits 值。

| 集合 | N | 浮点准确率/正确数 | 整数准确率/正确数 | 浮点-整数预测一致率/同类数 |
|---|---:|---:|---:|---:|
| validation | 2160 | 98.842593% (2135) | 98.842593% (2135) | 100.000000% (2160) |
| test | 2880 | 80.972222% (2332) | 81.250000% (2340) | 99.131944% (2855) |
| plate_validation | 1840 | 99.510870% (1831) | 99.510870% (1831) | 100.000000% (1840) |
| plate_test | 1360 | 99.117647% (1348) | 99.117647% (1348) | 100.000000% (1360) |

通用字体测试整数准确率为 81.25%，与车牌字模测试 99.117647% 相差明显，必须分别保留，不能只选最好一列。逐标量循环参考与向量化整数实现曾对验证集前 3 个样本做逐分数相等检查；3 个样本不是全数据或 FPGA 验证。板端 700 字符逐像素/逐分数比较属于另一层证据，见 [validation_data.md](validation_data.md)。

## 复现材料

发布包保留冻结binary、元数据、训练结果及历史训练/数据生成源码；保存的板测输入可以直接用整数参考复算。原历史工作区还保存浮点权重、数据NPZ和字模，文件身份在data_sources.json中记录；这些大体积训练输入不属于本包运行依赖。字体binary、上游vendor固定commit、完整训练环境锁及独立真实车牌划分的记录状态见[异常台账](anomaly_register.md)。从头重训与使用冻结权重推理是两个复现任务，本包优先保证后者。
