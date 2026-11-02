# 本次独立测试构建，不写正式工程或Flash。
set project_root [file normalize [file join [file dirname [info script]] ..]]
set out [file normalize [file join $project_root build engineering_03]]
if {[llength $argv]} {set out [file normalize [lindex $argv 0]]}
file mkdir $out
set root [file join $out sources]
puts [exec E:/Python/python.exe [file join $project_root scripts freeze_sources.py] $root]
cd $root
create_project -force autonomous_board [file join $out project] -part xc7a35tcpg236-1
set_property verilog_define {DIAG_JTAG LCD_SNAPSHOT} [current_fileset]
file mkdir [file join $out ip]
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name lcd_vio -dir [file join $out ip]
set config [list CONFIG.C_NUM_PROBE_IN 9 CONFIG.C_NUM_PROBE_OUT 3 CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 256 CONFIG.C_PROBE_IN2_WIDTH 128 CONFIG.C_PROBE_OUT0_WIDTH 16 CONFIG.C_PROBE_OUT1_WIDTH 2 CONFIG.C_PROBE_OUT2_WIDTH 11 CONFIG.C_PROBE_OUT0_INIT_VAL 0x0000 CONFIG.C_PROBE_OUT1_INIT_VAL 0x0 CONFIG.C_PROBE_OUT2_INIT_VAL 0x0 CONFIG.C_EN_PROBE_IN_ACTIVITY 0]
foreach n {3 4 5} {lappend config CONFIG.C_PROBE_IN${n}_WIDTH 256}
lappend config CONFIG.C_PROBE_IN6_WIDTH 32 CONFIG.C_PROBE_IN7_WIDTH 128 CONFIG.C_PROBE_IN8_WIDTH 128
set_property -dict $config [get_ips lcd_vio]
generate_target all [get_ips lcd_vio]
# 显式综合VIO IP，确保顶层综合能够解析调试模块。
synth_ip [get_ips lcd_vio]
set source_file [open [file join $root config rtl_sources.txt] r]
set sources [split [string trim [read $source_file]] "\n"]
close $source_file
foreach source $sources {read_verilog -sv [file join $root $source]}
read_xdc [file join $root constraints basys3_camera_lcd.xdc]
synth_design -top lcd_top -part xc7a35tcpg236-1
if {[llength [get_cells -hier -filter {REF_NAME =~ LD*}]]} {error "Unexpected latch"}
set camera_ibufs [get_cells -hier -filter {REF_NAME == IBUF && NAME =~ cam_data_IBUF*}]
if {[llength $camera_ibufs]!=8} {error "Expected8 camera input buffers"}
set_property IOBDELAY NONE $camera_ibufs
write_checkpoint -force [file join $out post_synth.dcp]
report_utilization -hierarchical -file [file join $out synth_utilization.rpt]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $out post_route.dcp]
report_utilization -hierarchical -file [file join $out utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $out timing.rpt]
report_bus_skew -file [file join $out bus_skew.rpt]
report_drc -file [file join $out drc.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
foreach delay {max min} {
 set paths [get_timing_paths -delay_type $delay -max_paths 1]
 if {![llength $paths] || [get_property SLACK $paths]<0} {error "Timing $delay failed"}
}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "Severe DRC"}
write_bitstream -force [file join $out autonomous_board.bit]
write_debug_probes -force [file join $out autonomous_board.ltx]
puts "PASS AUTONOMOUS_BOARD_BUILD"
