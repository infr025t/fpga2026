# fpga2026

基于Basys 3与OV7670 FIFO的FPGA图像处理和单目标定位项目，支持灰度/Sobel、ROI定位、1 bit打包、周期预览及UART接收。

- [项目首页与快速开始](demo/stream_image_demo/README.md)
- [操作手册](demo/stream_image_demo/docs/使用手册.md)
- [开发与验证](demo/stream_image_demo/docs/开发与验证.md)
- [本轮功能与验证记录](demo/stream_image_demo/docs/迭代记录_2026-10-22_周期预览.md)

在仓库根目录打开终端后，先进入项目目录，再运行项目文档中的命令：

```powershell
cd './demo/stream_image_demo'
python scripts/run_tests.py --python-only
```

当前源码通过63项Python测试、16组RTL仿真和7组协议交叉校验。随项目保留的bit是历史基础Demo，需重新构建才能使用当前功能；当前RTL尚未重新综合或上板。验证范围见[交付核验](demo/stream_image_demo/交付核验.json)。

本地临时工具、回归工作目录和历史ZIP不纳入Git；需要复现的验证证据保存在项目evidence目录。
