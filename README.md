# fpga2026

最新自查修复了提前到达的源结束状态丢失、屏幕配置误通过及Vivado失败汇总异常，详见[自查报告](stream_video_enhance/reports/rtl/self_check_2026-10-28/README.md)。当前屏幕物理接口保持8位。

基于 Basys 3 与 OV7670 FIFO 的 FPGA 视觉项目。已融合组员的 VGA 引导滤波分支，后续以 640×480 单尺度引导滤波为主线，原 QVGA 双尺度核心与串口 Demo 保留。正常计算不依赖 PC。

- [VGA 新工程与运行方式](stream_video_enhance/README.md)
- [分支差异与融合记录](stream_video_enhance/docs/merge_2026-10-27.md)
- [新运行时与验证范围](stream_video_enhance/reports/rtl/runtime/README.md)
- [TK040F1510 屏幕驱动、接线依据与自检](stream_video_enhance/docs/hardware/TK040F1510.md)
- [原 QVGA 工程与快速开始](demo/stream_image_demo/README.md)
- [原串口 Demo 操作手册](demo/stream_image_demo/docs/使用手册.md)
- [开发与验证](demo/stream_image_demo/docs/开发与验证.md)

在仓库根目录执行新工程软件测试；缺少 Vivado 时，依赖真实工具的测试会明确跳过：

```powershell
python -m pip install -r stream_video_enhance/model/requirements.txt
python -m unittest discover -s stream_video_enhance/tests -v
```

VGA 数值核心输出 632×472，四种模式为 RAW、BASE、DENOISE、ENHANCE；已归档组员的数值仿真与局部综合证据。有界入口、帧校验、异常恢复、完整输出 CRC 与独立报告邮箱见运行时报告。

2026-10-28：已依据用户提供的 TK040F1510 资料新增 NT35510 的 8 位 MCU8080 驱动、初始化、RGB565 窗口写入与独立屏幕自检顶层。800×480 面板清黑一次后，每帧更新完整 632×472 有效区，载荷减少约 22%。该顶层用于核实屏幕，尚未连接相机/算法运行时；实际板版、接线、电源与上板显示仍待核验。物理相机 VGA 适配、全系统时序与 Flash 冷启动也未完成，仓库没有新版整机 bit。

屏幕适配阶段（3beefb2）新工程 Python 测试发现 103 项，96 项通过、7 项因缺少 Vivado 明确跳过；屏幕 RTL 的 10 项检查全部符合预期，包括 4 项非法时序参数拒绝、完整面板与有效区域逐像素核对。另以真实核心核对 4 帧共 256 个输出，确认新增显示文件未破坏运行时编译与数值行为。详细范围与证据见[屏幕回归报告](stream_video_enhance/reports/rtl/screen/README.md)。

旧工程保持原字节，本轮只读核对 861 个交付哈希通过。旧工程 86 项 Python 测试通过是 2026-10-27 的结果，本轮没有重复运行；其历史 20 组 RTL、8 组协议流及 bit 的范围见[旧版交付核验](demo/stream_image_demo/交付核验.json)，不能作为新 VGA 整机的验收结果。

本地临时工具、回归工作目录和历史ZIP不纳入Git；需要复现的验证证据保存在项目evidence目录。
