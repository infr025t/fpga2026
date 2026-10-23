# FPGA 独立视觉处理项目

基于 **Basys 3（XC7A35T）+ GYF-198 OV7670_FIFO（AL422B）**，按独立视觉系统流程推进。新核心 `vision_top` 不依赖 PC，完成本机启停、摄像头采集校验、双尺度保边增强、原图切换、抽帧/缩小、双槽整帧显示队列和状态监测。

摄像头沿用现有模组，**显示硬件待定**：目前提供 100 MHz 同步像素握手接口，物理显示驱动、引脚、电源分配和最终 Flash 启动需在硬件确定后完成。当前没有新核心的 bit；随项目提供的 `build/vivado/stream_top.bit` 是历史串口 Demo。

[独立视觉架构](docs/独立视觉架构.md) · [运行验证](#运行验证) · [原串口-demo](#原串口-demo) · [文件与文档索引](#文件与文档索引)

<a id="快速开始"></a>
<a id="先离线确认接收端"></a>

## 运行验证

下列终端命令均在本文件所在的 `stream_image_demo` 目录执行。离线测试使用 Python；RTL 仿真还需 Icarus 或 Vivado。

```powershell
python scripts/run_tests.py --python-only
python scripts/run_tests.py --simulator iverilog --iverilog-bin "你的Icarus安装目录/bin"
```

截至 2026-10-23，通过 **86 项 Python 测试、20 组 RTL 仿真、8 组协议流交叉校验**。独立整数模型核对了 223,828 个增强像素，以及顶层摄像头/原图/缩小路径的 67 个显示像素；还覆盖显示阻塞、整帧丢弃、SCCB 恢复、行数异常、采集超时与处理看门狗。详见[本轮证据](evidence/regression_20261023_vision/README.md)与[交付核验](交付核验.json)。

新核心可选输出 VST1 状态包，离线回放无需串口依赖：

```powershell
python pc/vision_status.py --input evidence/regression_20261023_vision/full/verify_vision_status/vision_status_wire.bin --out build/regression/status_replay --count 2
```

新核心的综合入口为 `scripts/synth_vision.tcl`：只做独立综合与资源预算检查，不生成板级 bit。目前未执行 Vivado 综合；流程、资源预算、接口和独立运行开关表见[独立视觉架构](docs/独立视觉架构.md)。

## 原串口 Demo

原 `stream_top` 保留灰度/Sobel、ROI 定位、1 bit 打包、周期预览及 PC 接收/重连功能，输出 318×238 图像，协议为 FPG1。其构建脚本和开关定义与新 `vision_top` 分开。

<a id="生成当前bit并上板"></a>

### 生成串口 Demo 的 bit 并上板

以下步骤仅构建 `stream_top`。需安装包含 `xc7a35tcpg236-1` 器件支持的 Vivado；历史工程使用 Vivado 2025.1。随包历史 bit 不包含当前 RTL 的后续功能，使用前需重新构建。

1. 按[接线表](docs/使用手册.md#接线与成像)连接模组，确认SIOC、SIOD、RST的开漏上拉网络。
2. 在新开的Vivado会话中，使用Tcl Console执行以下构建命令。将路径替换为实际解压目录；大括号可保留路径中的空格。

   ```tcl
   source {D:/你的项目目录/stream_image_demo/scripts/build.tcl}
   ```

   脚本完成综合、布局布线、时序检查并生成 `build/vivado/stream_top.bit`，同时更新该目录中的报告。需要保留随包的历史bit与报告时，先备份该目录。若需交互编辑工程，见[开发与验证](docs/开发与验证.md)。

3. 构建成功后，在Hardware Manager下载新生成的bit。将全部开关置0，再设置 **SW0=1**，按BTNC，先使用内部测试图。
4. 安装串口依赖并接收10帧：

   ```powershell
   python -m pip install -r pc/requirements.txt
   python pc/receiver.py --port COM10 --baud 1000000 --out received_frames --count 10
   ```

   `COM10`是示例，按电脑实际枚举的串口修改，并确保端口未被其他程序占用。

5. 内部图接收正常后，将 **SW0=0** 切到摄像头，再次运行接收命令。固定镜头与目标，调焦至图像清晰后再开启定位。

### 串口 Demo 操作入口

| 现在想做什么 | 阅读入口 |
|---|---|
| 切换灰度、边缘图或定位输出 | [常用开关组合](docs/使用手册.md#常用组合) |
| 高速定位时定期确认画面 | [周期预览](docs/使用手册.md#高速定位与周期预览)，配合`--display --hold-preview` |
| 长时间接收、断线重连或保留原始字节 | [持续接收](docs/使用手册.md#持续接收断线重连与原始录制) |
| 实时显示或读取定位结果 | [PC输出](docs/使用手册.md#pc输出) |
| 调整阈值、ROI或帧间等待 | [开关与模式](docs/使用手册.md#开关与模式) · [ROI与运行参数](docs/使用手册.md#roi与运行参数) |
| 接线、调焦或排查接收问题 | [接线与成像](docs/使用手册.md#接线与成像) · [诊断与异常恢复](docs/使用手册.md#诊断与异常恢复) |
| 修改代码、运行仿真或更新交付清单 | [开发与验证](docs/开发与验证.md) |

## 文件与文档索引

| 入口 | 用途 |
|---|---|
| [独立视觉架构](docs/独立视觉架构.md) | 流程图映射、算法、开关、显示与诊断接口、硬件边界 |
| [使用手册](docs/使用手册.md) · [开发与验证](docs/开发与验证.md) | 原串口 Demo 操作参考、两条构建路径与回归流程 |
| [rtl/](rtl/) · [constraints/](constraints/) | 新核心 vision_top 与原串口顶层 stream_top；板级显示约束待定 |
| [pc/](pc/) | FPG1 图像接收、VST1 状态解析、整数参考模型与测试 |
| [sim/](sim/) · [scripts/](scripts/) | RTL测试、构建、回归与交付校验脚本 |
| [完整代码.md](完整代码.md) | 自动生成的当前源码汇总 |
| [交付核验.json](交付核验.json) · [SHA256.json](SHA256.json) | 验证范围与当前文件哈希 |
| [最新回归证据](evidence/regression_20261023_vision/README.md) | 独立视觉系统仿真、像素模型核对与协议回放 |
| [docs/history/](docs/history/) | 旧核验清单和历史诊断记录 |

协议与迭代记录：

- [ROI定位协议FPG1 v2](docs/定位协议_FPG1v2.md) · [输出协议FPG1 v3](docs/输出协议_FPG1v3.md)
- [2026-10-22持续接收](docs/迭代记录_2026-10-22_持续接收.md)
- [2026-10-22周期预览](docs/迭代记录_2026-10-22_周期预览.md)
- [2026-10-20异常恢复](docs/迭代记录_2026-10-20_异常恢复.md)
- [2026-10-19输出提速](docs/迭代记录_2026-10-19_输出提速.md) · [2026-10-19 ROI定位](docs/迭代记录_2026-10-19.md)
- [2026-10-17可靠性修复](docs/迭代记录_2026-10-17.md)
- [历史开发与联调日志PDF](docs/开发与联调日志.pdf) · [可检索文本](docs/开发与联调日志.txt)

下一步按最终显示模组接入物理接口和时钟转换，再进行完整综合、布局布线、供电与上板验收，最后验证 Flash 掉电重启。颜色识别、12 Mbaud 和物理显示输出尚未实现。
