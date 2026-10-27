# 真实数值核心的坏帧恢复

[运行时报告](README.md) · [测试台](../../../sim/tb_runtime_recovery.sv)

测试连接实际 `ingress_guard → guided_core → core_crc_monitor`，不以假核心替代数值流水线。16×16 和 17×19，分别以 L_CORE=55/56 两种配置运行；四个正常帧依次为 RAW、BASE、DENOISE、ENHANCE，期望像素来自未修改的整数模型，完整 CRC 来自 Python zlib。

每种配置插入三个坏帧：窗口预热时坐标错误、已有有效输出前缀时协议错误、完整裁剪 EOF 后才收到源 ERROR。它们分别触发一次无效事件和实际流水线 abort；坏帧允许出现前缀，但绝不发布成功报告，也不改变 last_good。其后四个正常帧逐像素、坐标、标志和完整 CRC 全部恢复正确。

16×16 每构建比较 256 个正常输出像素；17×19 每构建比较 396 个。四种构建共 16 个正常帧、12 个无效帧、1,304 个正常参考像素。源 OK 分别在核心 EOF 之前、同沿和之后到达，断言报告恰在成功接受沿的下一沿发布，并检查计数快照、坏帧期间报告保持和最终计数恒等式。

本轮统一运行器另外复跑 16×16 的两种延迟；17×19 的完整统一回归见本目录最终证据。可独立复现：

```powershell
python stream_video_enhance/scripts/run_runtime_tests.py --simulator iverilog --iverilog-bin "你的Icarus目录/bin" --suite recovery --size 17 --output-dir stream_video_enhance/build/regression/recovery_check
```

这些是同步运行时行为仿真，不代表真实摄像头的源结束检查、屏幕呈现、物理恢复时间或板级时序通过。
