# 独立视觉核心回归证据

[架构与接口](../../docs/独立视觉架构.md) · [交付核验](../../交付核验.json)

本轮验证收尾日期为 2026-10-23。下列文件保留实际工具输出，目录中的本机绝对路径为执行时路径；复制后可从当前目录找到对应日志和输出。

| 目录或文件 | 范围 |
|---|---|
| [full/summary.json](full/summary.json) | 20 组 RTL 仿真与 8 组 UART 字节流校验全部通过；当时 Python 为 70+13=83 项 |
| [python_final/summary.json](python_final/summary.json) | 加入 3 项 Tcl 预算检查测试后的完整 Python 重跑，70+16=86 项通过；另回放 13 个 FPG1 包 |
| [增强模型报告](full/verify_enhance_core/golden.json) | 小图 100 个、完整 QVGA 223,728 个输出像素逐像素通过，包含原图、两级基底、增强、坐标和帧标记 |
| [顶层显示报告](full/verify_vision_top/golden.json) | 摄像头/内部图、原图/增强、缩小倍率 1/2/4 共 67 个像素通过 |
| [顶层仿真日志](full/verify_vision_top/simulate.log) | PC 缺席、显示阻塞、丢新帧、真实 SCCB/AL422 引脚模型、行数拒绝、超时恢复、抽帧、暂停和复位 |
| [缓冲测试日志](full/verify_stream_buffers/simulate.log) | FIFO 深度 1/3、满时替换、溢出、稳定握手、整帧提交、异常/中止/复位 |
| [状态 UART 字节流](full/verify_vision_status/vision_status_wire.bin) | 2 个实际 RTL UART 导出包，由 pc/vision_status.py 解码，快照、CRC 和计数器检查通过 |
| [source_sha256.json](source_sha256.json) | 此版本源码与约束快照；RTL 完整回归后未修改运行逻辑 |

完整回归保存 7 组 FPG1 共 39 包、31 张 PGM，另有 VST1 2 包。为控制体积，不保存编译器中间文件及 6.56 MB 的 QVGA 文本导出；增强报告保留独立模型结果哈希，重新运行 enhance_core 仿真可重建文本。小图和顶层文本导出已保留。

3 项 Tcl 测试使用真实 Tcl 解释器与模拟 Vivado 命令，只验证脚本语法、超预算拒绝和检查点调用次序。未运行 Vivado 综合或布局布线，也未进行真实摄像头、显示、电源或 Flash 启动验证。历史 bit 保持原样。

复现入口（项目目录执行）：

```powershell
python scripts/run_tests.py --python-only
python scripts/run_tests.py --simulator iverilog --iverilog-bin "你的Icarus安装目录/bin"
```
