# Flash 与上电启动

v1.1 的 `autonomous_board.bit` 已写入 Basys 3 板载 MX25L3273F（4 MiB），器件 ID 为 c2 20 16。擦除、空白检查、编程和回读校验全部通过。随后通过 JTAG 发出重新启动命令，由 JP1 所选 QSPI 加载，成功路径没有下载业务 BIT；匹配 VIO 被识别，1.5 秒间隔内视频帧计数增加 34，错误码为 0。

这验证了 Flash 内容和 QSPI 加载后的运行；本轮没有执行人工断电重启或新增屏幕目视检查。前一轮 RAM 测试与本次 Flash 安装使用同一 BIT，SHA256 见[发布清单](../../release/release_manifest.json)。完整[安装记录](../../evidence/flash_install/installation.json)、[编程日志](../../evidence/flash_install/program.log)及[启动日志](../../evidence/flash_install/boot_verified.log)保留原始证据。

## 使用

JP1 保持 QSPI，正常供电即可启动，不需要 PC 逐次下载。SW4=0 时由 SW3 选择 RAW（0）或 EDGE（1）；SW4=1 为 OCR，SW5=0 暗字、SW5=1 白字。正常运行其他诊断开关置0，调试覆盖保持关闭。已有接线不变。

## 再次安装

在 `project/` 下使用 Vivado 2025.1 执行以下顺序。`<输出目录>` 要替换成绝对路径、每次新建，保存旧 Flash 备份；不要把旧备份删掉以绕过保护。

```powershell
vivado -mode batch -source scripts/flash_program.tcl -tclargs backup ../release <输出目录> ../release mx25l3273f-spi-x1_x2_x4 210183BCBF83A
vivado -mode batch -source scripts/flash_program.tcl -tclargs program ../release <输出目录> ../release mx25l3273f-spi-x1_x2_x4 210183BCBF83A
vivado -mode batch -source scripts/verify_flash_boot.tcl
```

backup 保存完整 4 MiB 内容；program 要求备份存在，从当前 BIT 重新生成 MCS，并保留器件 ID 核对和校验；两者结束后恢复当前业务 RAM 程序。最后一步实际从 QSPI 重新加载，不以恢复 RAM 后的画面代替 Flash 验证。启动检查要求视频运行，执行前请使 SW15=0、相机连接正常。另一个板卡必须核实其 Flash 型号和 JTAG 序列号后再使用，不能套用当前设备身份。

本次旧 Flash 备份保存在本机 `E:/FPGA_Test_Work/plate_blue_polarity_v1_1/flash_install/flash_before.bin`，大小和 SHA256 记入安装记录，不作为新版业务镜像上传。通用 RAM 下载及 VIO 操作仍使用 `hardware.tcl`，不会修改 Flash。
