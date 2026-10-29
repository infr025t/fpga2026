# NT35510接口保留情况

保留最新main的8位MCU8080总线、初始化、窗口写入和独立屏幕自检。厂商资料的规范化寄存器表、来源身份与等待约束保存在hardware/中的profile和sources JSON；generate_nt35510_rom.py继续执行最新版严格检查。

外部接口：lcd_data[7:0]、lcd_cs_n、lcd_rs、lcd_wr_n、lcd_rd_n、lcd_reset_n、lcd_bl。写专用时RD保持高，命令与参数均为16位、先高后低；RGB565每像素两个字节。横屏800×480，整屏先清黑，再写630×470有效窗口x=85..714、y=5..474。

与新算法的边界：edge_uart_stream输出display_valid/pixel/raw/edge/x/y/frame_id及SOF/EOL/EOF。这些就是UART所使用的同一输出节点，不经PC重算。edge_display_stream_if将Y复制为RGB565并把全局x加80，映射到居中640×480画布；边框需由显示控制器清黑。接口不对计算核心施加ready反压。

当前edge_top为相机+UART上板入口，未引出未知LCD线序；完整显示支路的帧接纳、有限缓存和实际连线仍须单独集成。不能把没有缓存的valid信号直接接到可能等待的8080写入器，造成像素丢失。独立nt35510_bringup_top可在确认线序后单独综合，用于屏幕初始化与画布自检；本版未给未确认的LCD引脚编造约束。

已用物理引脚模型重验总线时序、初始化、窗口、复位和800×480清黑及630×470全像素写入。该证据不等于实物点亮或摄像头到LCD整链验收。
