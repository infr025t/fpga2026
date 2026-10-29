# Basys 3 XC7A35T CPG236, from Digilent Basys-3-Master.xdc.
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk100]
create_clock -name sys_clk -period 10.000 [get_ports clk100]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports btnC]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS33} [get_ports uart_txd]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS33} [get_ports {sw[3]}]
set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports {sw[4]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {sw[5]}]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {sw[6]}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports {sw[7]}]
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {sw[8]}]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33} [get_ports {sw[9]}]
set_property -dict {PACKAGE_PIN T2 IOSTANDARD LVCMOS33} [get_ports {sw[10]}]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD LVCMOS33} [get_ports {sw[11]}]
set_property -dict {PACKAGE_PIN W2 IOSTANDARD LVCMOS33} [get_ports {sw[12]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33} [get_ports {sw[13]}]
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33} [get_ports {sw[14]}]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {sw[15]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {led[7]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports {led[8]}]
set_property -dict {PACKAGE_PIN V3 IOSTANDARD LVCMOS33} [get_ports {led[9]}]
set_property -dict {PACKAGE_PIN W3 IOSTANDARD LVCMOS33} [get_ports {led[10]}]
set_property -dict {PACKAGE_PIN U3 IOSTANDARD LVCMOS33} [get_ports {led[11]}]
set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports {led[12]}]
set_property -dict {PACKAGE_PIN N3 IOSTANDARD LVCMOS33} [get_ports {led[13]}]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports {led[14]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports {led[15]}]
set_property -dict {PACKAGE_PIN J1 IOSTANDARD LVCMOS33} [get_ports {cam_data[0]}]
set_property -dict {PACKAGE_PIN L2 IOSTANDARD LVCMOS33} [get_ports {cam_data[1]}]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports {cam_data[2]}]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports {cam_data[3]}]
set_property -dict {PACKAGE_PIN H1 IOSTANDARD LVCMOS33} [get_ports {cam_data[4]}]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports {cam_data[5]}]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports {cam_data[6]}]
set_property -dict {PACKAGE_PIN G3 IOSTANDARD LVCMOS33} [get_ports {cam_data[7]}]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports cam_sioc]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports cam_siod]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports cam_vsync]
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports cam_wen]
set_property -dict {PACKAGE_PIN L17 IOSTANDARD LVCMOS33} [get_ports cam_rrst_n]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports cam_rclk]
set_property SLEW SLOW [get_ports {cam_rclk cam_rrst_n cam_wen cam_sioc cam_siod}]
set_property DRIVE 8 [get_ports {cam_rclk cam_rrst_n cam_wen cam_sioc cam_siod}]
# Async human/frame signals are sampled through marked synchronizers.
set_false_path -from [get_ports {btnC sw[*] cam_vsync}]
set_false_path -from [get_ports {cam_siod cam_sioc}]
set_max_delay 20 -datapath_only -from [get_clocks sys_clk] -to [get_ports {led[*] uart_txd cam_wen cam_rrst_n cam_sioc cam_siod}]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

# JC9: camera RESET# open-drain, external pullup to allowed camera IO rail.
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 8} [get_ports cam_rst_n]
set_max_delay 20 -datapath_only -from [get_clocks sys_clk] -to [get_ports cam_rst_n]

# JC10: passive HREF diagnostic input, double-flop synchronized.
# Weak pulldown keeps diagnostics quiet if the extra wire is absent.
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33 PULLDOWN TRUE} [get_ports cam_href]
set_false_path -from [get_ports cam_href]

# Variable-period RCLK: phase-tested earliest sampling is 40 ns after launch.
# External AL422 TAC15 ns + assumed board flight/skew10 ns =25 ns.
# Explicit budgets cover clock-Q-to-pad5ns + pad-to-sampling-FF7ns.
# Together with25ns external allowance this leaves3ns for setup/skew at40ns.
set_property IOB TRUE [get_ports cam_rclk]
set_property SLEW FAST [get_ports cam_rclk]
set_max_delay 5.000 -datapath_only -from [get_pins -hier -filter {NAME =~ camera/rclk_reg/Q}] -to [get_ports cam_rclk]
# Input arrival already includes the25ns external budget; total32 leaves7ns inside.
set_max_delay 32.000 -datapath_only -from [get_ports {cam_data[*]}]
set_min_delay 0.000 -from [get_ports {cam_data[*]}]
# Virtual fastest16.667MHz read clock labels the external arrival assumptions.
create_clock -name fifo_virtual -period 60.000
set_input_delay -clock fifo_virtual -max 25.000 [get_ports {cam_data[*]}]
set_input_delay -clock fifo_virtual -min 0.000 [get_ports {cam_data[*]}]

# Preserve the current reader RCLK electrical setting.
set_property DRIVE 4 [get_ports cam_rclk]

# Camera WRST is independent of VSYNC. Basys3 JB1=A14.
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33 DRIVE 4 SLEW SLOW} [get_ports cam_wrst_n]
set_max_delay 20 -datapath_only -from [get_clocks sys_clk] -to [get_ports cam_wrst_n]
