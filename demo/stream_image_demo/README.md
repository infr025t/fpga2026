# FPGA 图像处理与单目标定位 Demo

基于 **Basys 3（XC7A35T）+ GYF-198 OV7670_FIFO（AL422B）**：采集320×240图像，输出318×238灰度图或Sobel边缘图，通过1 Mbps UART传到PC；支持ROI阈值定位、1 bit边缘图和仅定位结果输出。

**使用当前功能前，需从当前RTL重新生成bit。** 随项目提供的 `build/vivado/stream_top.bit` 是历史Demo，不包含后续诊断、ROI定位、提速、异常恢复与周期预览改动。历史实板已跑通基础图像链路；当前源码截至2026-10-22通过63项Python测试、16组RTL仿真和7组协议交叉校验，尚未重新综合实现或上板。验证范围见 [交付核验](交付核验.json)。

[快速开始](#快速开始) · [下一步](#下一步) · [文件与文档索引](#文件与文档索引)

## 快速开始

下列终端命令均在本文件所在的 `stream_image_demo` 目录执行。Python用于接收与测试；硬件构建需安装包含 `xc7a35tcpg236-1` 器件支持的Vivado，历史工程使用Vivado 2025.1。

### 先离线确认接收端

不接开发板也可运行，以下两条命令只需要Python标准库：

```powershell
python scripts/run_tests.py --python-only
python pc/receiver.py --input evidence/regression_20261020_recovery/full/verify_top_recovery/top_recovery_wire.bin --out build/regression/readme_replay --count 3
```

回放应保存3张PGM及对应JSON、CSV，帧序号为1、4、5；空号2、3是仿真中被丢弃的超时采集。输出位于 `build/regression/readme_replay/`。

### 生成当前bit并上板

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

## 下一步

| 现在想做什么 | 阅读入口 |
|---|---|
| 切换灰度、边缘图或定位输出 | [常用开关组合](docs/使用手册.md#常用组合) |
| 高速定位时定期确认画面 | [周期预览](docs/使用手册.md#高速定位与周期预览)，配合`--display --hold-preview` |
| 实时显示或读取定位结果 | [PC输出](docs/使用手册.md#pc输出) |
| 调整阈值、ROI或帧间等待 | [开关与模式](docs/使用手册.md#开关与模式) · [ROI与运行参数](docs/使用手册.md#roi与运行参数) |
| 接线、调焦或排查接收问题 | [接线与成像](docs/使用手册.md#接线与成像) · [诊断与异常恢复](docs/使用手册.md#诊断与异常恢复) |
| 修改代码、运行仿真或更新交付清单 | [开发与验证](docs/开发与验证.md) |

## 文件与文档索引

| 入口 | 用途 |
|---|---|
| [使用手册](docs/使用手册.md) · [开发与验证](docs/开发与验证.md) | 操作参考、构建与验证流程 |
| [rtl/](rtl/) · [constraints/](constraints/) | RTL与Basys 3约束；顶层为stream_top.sv |
| [pc/](pc/) | 接收器、依赖与协议测试 |
| [sim/](sim/) · [scripts/](scripts/) | RTL测试、构建、回归与交付校验脚本 |
| [完整代码.md](完整代码.md) | 自动生成的当前源码汇总 |
| [交付核验.json](交付核验.json) · [SHA256.json](SHA256.json) | 验证范围与当前文件哈希 |
| [最新回归证据](evidence/regression_20261022_preview/) | 周期预览回归日志、UART流和解码结果 |
| [docs/history/](docs/history/) | 旧核验清单和历史诊断记录 |

协议与迭代记录：

- [ROI定位协议FPG1 v2](docs/定位协议_FPG1v2.md) · [输出协议FPG1 v3](docs/输出协议_FPG1v3.md)
- [2026-10-22周期预览](docs/迭代记录_2026-10-22_周期预览.md)
- [2026-10-20异常恢复](docs/迭代记录_2026-10-20_异常恢复.md)
- [2026-10-19输出提速](docs/迭代记录_2026-10-19_输出提速.md) · [2026-10-19 ROI定位](docs/迭代记录_2026-10-19.md)
- [2026-10-17可靠性修复](docs/迭代记录_2026-10-17.md)
- [历史开发与联调日志PDF](docs/开发与联调日志.pdf) · [可检索文本](docs/开发与联调日志.txt)

后续方向：当前RTL上板验收、采集与发送重叠，再评估VGA与更高串口速率。颜色识别、12 Mbaud和VGA连续处理尚未实现。
