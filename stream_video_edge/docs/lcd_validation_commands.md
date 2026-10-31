# LCD低速回归命令
在stream_video_edge目录运行；不同运行必须使用新标签，避免覆盖证据。Python依赖为requirements.txt中的numpy、Pillow、pyserial，测试使用内置unittest，不需要pytest。
~~~powershell
E:/Python/python.exe -m unittest discover -s tests -v
E:/Python/python.exe scripts/run_camera_tests.py --tag YOUR_UNIQUE_TAG
E:/Python/python.exe scripts/run_lcd_tests.py YOUR_SMALL_TAG tb_display_path
E:/Python/python.exe scripts/run_lcd_tests.py YOUR_ADMISSION_TAG tb_lcd_admission
E:/Python/python.exe scripts/run_lcd_tests.py YOUR_VGA_TAG tb_video_path --vga
E:/Python/python.exe scripts/run_uart_tests.py --tag YOUR_UART_TAG
powershell -ExecutionPolicy Bypass -File build_lcd.ps1
powershell -ExecutionPolicy Bypass -File program_lcd.ps1
~~~
仿真、构建和发布后验收是不同层次。camera模型通过不证明真实引脚电气；内部完整输出CRC和软件参考匹配可覆盖全部确定性输出，实拍只做计数、送屏CRC和人工观察，不能声称逐像素对真实场景参考完全相同。

## JTAG单张与连拍
退出Vivado图形界面的硬件连接后使用同一Basys3；脚本不会访问COM15。
Vivado参数顺序必须先-log/-journal，再-tclargs；手动调用时建议把日志放E:/FPGA_Test_Work。
~~~powershell
vivado -mode batch -source scripts/lcd_hardware.tcl -tclargs one 1 INTERNAL_RAW 4186065429
vivado -mode batch -source scripts/lcd_hardware.tcl -tclargs one 5 INTERNAL_GUIDED 264883040
vivado -mode batch -source scripts/lcd_hardware.tcl -tclargs one 13 INTERNAL_GAUSSIAN 207516
vivado -mode batch -source scripts/lcd_live.tcl -tclargs YOUR_CAMERA_LABEL 4 50
vivado -mode batch -source scripts/lcd_hardware.tcl -tclargs physical
~~~
MODE0为RAW，4为引导EDGE，12为高斯EDGE；内部源加1。连拍最后参数是可选的记录帧数上限，0或省略为持续运行。有限测试必须以RECORDED_FRAME_LIMIT结束才通过；错误或提前复位返回失败。无限连拍以BTNC或在该标签目录建立stop.flag停止。退出监控会暂停新帧；最后一条physical交回实体开关。

Snapshot为可选诊断构建，不是默认已上板bit。需另建OutDir，用build_lcd.ps1 -Snapshot；每次program/one/dump/live均需在-tclargs最后加-snapshot以选对应探针。快照只抽样，不控制视频链路。
