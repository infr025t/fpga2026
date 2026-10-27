# fpga2026

基于 Basys 3 与 OV7670 FIFO 的 FPGA 视觉项目。已融合组员的 VGA 引导滤波分支，后续以 640×480 单尺度引导滤波为主线，原 QVGA 双尺度核心与串口 Demo 保留。正常计算不依赖 PC。

- [VGA 新工程与运行方式](stream_video_enhance/README.md)
- [分支差异与融合记录](stream_video_enhance/docs/merge_2026-10-27.md)
- [新运行时与验证范围](stream_video_enhance/reports/rtl/runtime/README.md)
- [原 QVGA 工程与快速开始](demo/stream_image_demo/README.md)
- [原串口 Demo 操作手册](demo/stream_image_demo/docs/使用手册.md)
- [开发与验证](demo/stream_image_demo/docs/开发与验证.md)

在仓库根目录执行新工程软件测试；缺少 Vivado 时，依赖真实工具的测试会明确跳过：

```powershell
python -m pip install -r stream_video_enhance/model/requirements.txt
python -m unittest discover -s stream_video_enhance/tests -v
```

VGA 数值核心输出 632×472，四种模式为 RAW、BASE、DENOISE、ENHANCE；已归档组员的数值仿真与局部综合证据。当前新增有界入口、帧校验、异常恢复、完整输出 CRC 与独立报告邮箱，具体本轮结果见运行时报告。物理相机 VGA 适配、NT35510 实物接口核实、全系统时序与 Flash 冷启动仍未完成，仓库没有新版整机 bit。

旧工程本轮保持原字节，86 项 Python 测试和 861 个交付哈希重新核对通过；其历史 20 组 RTL、8 组协议流及 bit 的范围见[旧版交付核验](demo/stream_image_demo/交付核验.json)，不能作为新 VGA 整机的验收结果。

本地临时工具、回归工作目录和历史ZIP不纳入Git；需要复现的验证证据保存在项目evidence目录。
