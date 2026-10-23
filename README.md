# fpga2026

基于 Basys 3 与 OV7670 FIFO 的 FPGA 视觉项目。按独立运行流程实现了摄像头采集、双尺度保边增强、本机控制、整帧显示队列与性能监测；PC 作为可选诊断端。

- [项目首页与快速开始](demo/stream_image_demo/README.md)
- [独立视觉架构与接口](demo/stream_image_demo/docs/独立视觉架构.md)
- [原串口 Demo 操作手册](demo/stream_image_demo/docs/使用手册.md)
- [开发与验证](demo/stream_image_demo/docs/开发与验证.md)

在仓库根目录打开终端后，先进入项目目录，再运行项目文档中的命令：

```powershell
cd './demo/stream_image_demo'
python scripts/run_tests.py --python-only
```

当前通过 86 项 Python 测试、20 组 RTL 仿真与 8 组协议录制流校验；增强结果逐像素比对 223,828 个输出像素。显示硬件待定，新核心提供通用显示接口，尚未完成显示适配、Vivado 综合、Flash 启动与实板验收。随项目保留的 bit 属于历史串口 Demo。验证范围见[交付核验](demo/stream_image_demo/交付核验.json)。

本地临时工具、回归工作目录和历史ZIP不纳入Git；需要复现的验证证据保存在项目evidence目录。
