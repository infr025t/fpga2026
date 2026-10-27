# 完整输出 CRC 与不可变报告验证

日期：2026-10-27。新增 `crc32_byte.sv`、`core_crc_monitor.sv`；未修改数值核心、模型、profile 或既有质量报告。该阶段仅验证同步运行时报告，不证明物理相机、屏幕、板级时序或 Flash 启动。

## 接口与提交时序

两套 CRC 覆盖裁剪区域的全部有效 RAW/selected 字节，与快照、ROI、显示或串口是否读取无关。多项式为反射 `0xEDB88320`，初值与最终异或均为 `0xFFFFFFFF`；每拍展开 8 个固定步骤，支持连续每拍一字节。

`core_done_valid` 为当前有效输出 EOF 的组合预览；`core_done_ok` 同时检查坐标、帧号、标志和 `(W-8)*(H-8)` 像素数。EOF 当拍包含最后字节并保存独立 pending 描述符；匹配 source/guard success 可先于、同时或晚于 EOF。两者齐备的接受沿之后，下一上升沿发布 latest，采样当时三个已注册运行计数。invalid/abort 会取消未发布结果，保留 last_good；reset 清除报告有效标志。

输入接受描述符、当前输出 CRC 上下文、待提交 EOF、latest 和 claimed 为独立寄存器。旧帧 EOF/success 与新帧输入 SOF 同沿时，旧 pending 保留旧配置，新输入描述符保存新配置。publication 与新输入接受同沿时，提交计数取该沿的 pre-edge 值，后续运行计数不修改已提交报告。

claim 成功时 `claimed_valid` 脉冲一拍，`claimed_report` 持续保持，直到下一次成功 claim。同沿 claim/publication 领取旧 latest，新报告仍为 unclaimed；已在该沿领取的旧报告不增加覆盖计数。无人领取而覆盖旧 latest 才使 `overwrite_count` 饱和递增，diagnostic_seq 与 frame_id 采用模计数。

## 实际测试

先创建行为 bench，再在 DUT 文件尚不存在时实际编译失败，日志见 [crc_red/compile.log](crc_red/compile.log)。实现后的 Icarus 仿真通过，见 [crc_green/simulate.log](crc_green/simulate.log)；最终结果为 **113 次发布、9,046 拍**，编译日志为空（无诊断）。源码哈希和已知 CRC 常量见 [crc_results.json](crc_results.json)。

- `123456789` → `0xCBF43926`，空输入、单字节 0/255；64 字节整图结果由 Python `zlib.crc32` 独立生成。
- RAW/selected 分开、RAW 模式相等、首/末字节改变、有效像素间空拍、帧内修改配置、success 早/晚/同沿到达。
- 正好下一沿发布；claim/publication 同沿；100 次后续报告发布时 claimed 字节保持；提交计数快照与新输入接受同沿。
- 旧 EOF/success 与新输入 SOF 同沿，旧报告不混入新配置；重复 SOF、错误坐标、提前 EOF 和错误帧号 success 均不发布成功结果。
- EOF 同沿 abort/reset、等待提交期间 abort、发布沿或 EOF 同沿 invalid；之后新完整帧正常恢复。
- 将计数寄存器直接置于临界值以缩短测试，验证覆盖计数饱和、diagnostic_seq 回绕，以及 `frame_id=0xFFFFFFFF→0`。

运行命令（仓库根目录，工具目录按实际安装设置）：

```powershell
iverilog -g2012 -s tb_core_crc -o build/regression/crc_agent_green/test.vvp stream_video_enhance/rtl/video_runtime_pkg.sv stream_video_enhance/rtl/crc32_byte.sv stream_video_enhance/rtl/core_crc_monitor.sv stream_video_enhance/sim/tb_core_crc.sv
vvp build/regression/crc_agent_green/test.vvp
```

本 bench 使用 16×16 输入对应的 8×8 裁剪结果，专门检查 CRC 与控制边界；全 VGA 及真实 guided_core 的逐像素验证属于整链运行时 bench，不能用本结果替代。
