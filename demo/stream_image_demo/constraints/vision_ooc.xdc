# Generic core only; no screen pin assignment or display PHY is chosen yet.
create_clock -name sys_clk -period 10.000 [get_ports clk100]
set_false_path -from [get_ports {btnC sw[*] cam_vsync cam_href cam_sioc cam_siod}]
# Other I/O timing belongs to the eventual board/display wrapper.
