# 高斯／Sobel串口调试
与LCD入口共用相机读取和高斯/Sobel核心，仅UART调试时下载artifacts/edge_top.bit/ltx；正常LCD用lcd_top.bit/ltx。相机接线相同，额外串口为Basys3板载USB-UART，无需改COM15。
SW0为相机/内部源，SW1为RAW/EDGE，SW12:4全0使用T128，否则min(4N,2040)；SW15上升沿触发单张。SW2算法选择取消。UART RAW裁到与EDGE相同的630×470，PC只补黑边显示。
执行build.ps1、program.ps1、receive_one.ps1。自动采集可用pc/receive.py --auto --rounds1（RAW/EDGE两张）或--frames50（精确50张）。每次标签和输出目录不覆盖旧记录。
新程序只输出高斯标识1，EVG2保留字段64不参与算法。旧引导模式已删除，新接收程序不接受其数据。默认阈值128，自动阈值未实现。
