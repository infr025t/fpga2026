# PC观察与参考工具

PC工具用于保存板端输出并作独立整数参考比较。自主模式的定位、分割、归一化、CNN和结果发布在FPGA端完成；PC参考程序不是板端计算链的组成部分，也不向该自主观察链发送推理请求。

## 文件职责

| 文件 | 职责与边界 |
|---|---|
| `pc/auto_protocol.py` | 字节流同步、包长度/字段/CRC验证；支持AIF1、ASG1至ASG5、ACR2、AER1。 |
| `pc/auto_capture.py` | 从文件或只读串口接收，原始字节落盘，驱动解析和帧收集，关闭数据源后返回采集统计。内部函数参数由CLI校验。 |
| `pc/auto_collect.py` | 按epoch与frame_id分组，最多保留8组未完成帧，输出完整组及拒绝记录；包含JSON字节编解码。 |
| `pc/auto_verify.py` | 对完整组独立计算ROI、字符框、归一化像素、36个有符号分数和argmax，保存逐帧数组与差异。 |
| `pc/observe_auto.py` | 原有CLI参数、输出目录保护、采集后模型哈希校验、逐帧验证、真值评分和汇总；显式导出旧FrameCollector、JSON函数和verify_frame以兼容现有导入。 |
| `pc/plate_locator.py`、`segment_ref.py`、`norm_ref.py`、`integer_cnn.py` | 独立参考定位、分割、归一化与整数CNN；本次未改数学、模型和阈值。 |

`verify_board.py`、`verify_normalization_board.py`、`verify_segment_board.py`及相关协议工具属于历史请求/响应验证入口，不能据本观察器的只读属性推断它们也只读。软件拆分以单元测试和wire回放验证；当前板端采集另见[当前验证](current_validation.md)。

## v1.1 白字模式与协议兼容

AIF1中的原图仍是未反相的160×120灰度小图，flags=0表示暗字，flags=2表示白字。`auto_verify.py`对动态定位合同接受这两个值：先在原图上调用定位器，再把同一个flags传给分割与归一化，最后用原冻结CNN权重比较分数。不得先把raw整体反相再定位，也不得把AIF1当成已反相图再次翻转。

协议魔数、字段布局和旧flags=0语义不变；旧wire可继续回放。SW5不替代人工上传协议中的flags。白字同图证据见[白字支持](white_character_support.md)，板测状态以[当前验证](current_validation.md)为准。v1.1的61项PC回归与白字整链wire核验结果见[新增仿真汇总](../../evidence/blue_polarity/simulation_summary.json)。

## CLI与采集边界

从`project/`目录运行；输出目录必须为新目录：

```powershell
python -B pc/observe_auto.py --wire ../evidence/baseline/reports/split_aligned_repeat_100/wire.bin --frames 100 --truth BD12345 --out reports/replay_new
```

省略`--wire`时CLI只接受`--port COM10 --baud 12000000`，缺省也是该组合；`--frames`缺省20，`--timeout`缺省30秒且均须为正。COM15不被CLI接受。观察串口禁用流控，只读不写。

采集以4096字节为读取单位，整块原始字节先写入`wire.bin`。达到所请求的完整组数量后，同一块剩余字节仍留在wire证据中，但不继续接纳新的帧组；不会为补足“验证通过”数量而延长接收。采集结束时解析残留字节，将未完成组写入`rejected_groups.jsonl`。参考计算发生在数据源关闭之后，不在接收循环内运行。

帧组必须具备AIF1、一个ASG版本、AER1和声明数量的全部ACR2，字符索引必须完整且唯一；状态非零、重复包、数量不符、越界索引和重复完整帧会被拒绝。frame_id回退产生新epoch并清理上一轮未完成组；超过8组上限时淘汰最早组并计数。ASG2至ASG5共享分组槽，但保留原magic供参考算法选择对应版本。

## 如何读结果

- `captured_complete_frames`：协议包完整且分组约束通过的组数，不是识别正确数。
- `verified_frames`：完整组中逐框、逐像素、逐分数、argmax和文本与独立整数参考一致的帧数。错误模型哈希也会使该帧失败。
- 汇总`passed`：`verified_frames >= requested_frames`，且无采集错误、模型错误。它不要求`incomplete_groups`为零，也不代表所有源帧均被采集或识别正确。
- `--truth`仅在计算完成后比较硬件文本，保存`truth_exact_frames`，不参与参考算法，不改变参考一致性的`passed`。错误真值可出现`passed=true`且`truth_exact_frames=0`。
- 不完整组、无效组、丢弃/截断字节和源frame_id间隙分别保留，不能放入“成功帧”分子或从数据完整性说明中删去。`observed_source_frame_gaps`也不能单独推断为串口丢包率。
- 空白图像可形成0字符且参考一致的完整组；这不代表成功识别一个车牌。回放耗时是本机回放和参考计算耗时，不是板端视频帧率或OCR速率。

每帧保存`packets.json`、`raw.npy`、`arrays.npz`和`result.json`。汇总在`summary.json`，原始流在`wire.bin`。数组包括板端/参考归一化图和板端/参考36维分数。

## v1.0 PC拆分验证证据

本次证据位于[reports/pc_refactor](../../evidence/validation/pc_refactor)：

- [before_observer_tests.log](../../evidence/validation/pc_refactor/before_observer_tests.log)：拆分前12项观察器测试通过。
- [red_capture_tests.log](../../evidence/validation/pc_refactor/red_capture_tests.log)：新增独立采集边界测试先因缺少模块而失败。
- [after_all_tests.log](../../evidence/validation/pc_refactor/after_all_tests.log)：拆分后全部61项PC测试通过，包含原12项观察器测试及2项新增采集边界测试。
- [replay_comparison.json](../../evidence/validation/pc_refactor/replay_comparison.json)：旧入口与新入口对同一历史wire回放；100帧、700字符参考一致，逐帧JSON、原始图、分组包、wire与拒绝记录一致，NPZ中的每个数组一致。6个抽取定义的AST与旧源一致。
- [current_replay/summary.json](../../evidence/validation/pc_refactor/current_replay/summary.json)：该固定历史数据的真值文本为`BD12345`，100帧文本匹配；仍记录1个不完整组、1200截断字节。不能扩展为任意车牌或本次新BIT实测准确率。
- [commands.md](../../evidence/validation/pc_refactor/commands.md)：确切复现命令及比较范围。
- [source_manifest.json](../../evidence/validation/pc_refactor/source_manifest.json)：本次PC源、测试、模型、文档和验证报告SHA256。该清单只冻结PC验证范围，不代替整机工程清单。

历史采集来自`evidence/baseline/reports/split_aligned_repeat_100/wire.bin`，SHA256为`989bf5397c65ba62b35dd63af0c94a62c0cab735ef1d0e7ac46faf8363894cb2`。模型SHA256为`179d6d9b9a4e2229c152770152fe6c8d71ff924af5d9da06132debd730cf4645`。历史回放输入保存在evidence/baseline，新的输出写入project/reports。

仅比较新旧回放时忽略`capture_seconds`和`total_seconds`；与历史实串口汇总比较时再忽略`source`。这些字段因运行时间和数据源形式而异，其余汇总语义字段及100帧结果与历史证据相同。
