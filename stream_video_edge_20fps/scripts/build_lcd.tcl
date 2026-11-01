set root [file normalize [file join [file dirname [info script]] ..]]
set out [lindex $argv 0]
if {$out eq {}} {set out {E:/FPGA_Test_Work/edge20fps_build}}
set out [file normalize $out]
set snapshot_arg [lindex $argv 1]
if {$snapshot_arg eq {}} {set snapshot_arg 1}
if {$snapshot_arg ni {0 1}} {error "Snapshot argument must be 0 or 1"}
set snapshot $snapshot_arg
set stat_frames [lindex $argv 2]
if {$stat_frames eq {}} {set stat_frames 0}
if {![string is integer -strict $stat_frames] || $stat_frames<0} {error "STAT_FRAMES must be a nonnegative integer"}
# 构建目录必须独立，避免覆盖仓库内经过实板验证的产物。
if {[string equal -nocase $out $root] || [string first [string tolower "${root}/"] [string tolower "${out}/"]]==0} {error "OutDir must be outside the source tree"}
set name [expr {$snapshot?{lcd_top_snapshot}:{lcd_top}}]
file mkdir $out
create_project -force lcd_v04 [file join $out project] -part xc7a35tcpg236-1
set defines {DIAG_JTAG}
if {$snapshot} {lappend defines LCD_SNAPSHOT}
set_property verilog_define $defines [current_fileset]
file mkdir [file join $out ip]
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name lcd_vio -dir [file join $out ip]
set config [list CONFIG.C_NUM_PROBE_IN [expr {$snapshot?8:4}] CONFIG.C_NUM_PROBE_OUT [expr {$snapshot?3:2}] CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 256 CONFIG.C_PROBE_IN2_WIDTH 128 CONFIG.C_PROBE_OUT0_WIDTH 16 CONFIG.C_PROBE_OUT1_WIDTH 2 CONFIG.C_PROBE_OUT0_INIT_VAL 0x0000 CONFIG.C_PROBE_OUT1_INIT_VAL 0x0 CONFIG.C_EN_PROBE_IN_ACTIVITY 0]
if {$snapshot} {
 for {set i 3} {$i<=5} {incr i} {lappend config CONFIG.C_PROBE_IN[set i]_WIDTH 256}
 lappend config CONFIG.C_PROBE_IN7_WIDTH 128 CONFIG.C_PROBE_IN6_WIDTH 32 CONFIG.C_PROBE_OUT2_WIDTH 11 CONFIG.C_PROBE_OUT2_INIT_VAL 0x0
} else {lappend config CONFIG.C_PROBE_IN3_WIDTH 256}
set_property -dict $config [get_ips lcd_vio]
generate_target all [get_ips lcd_vio]
synth_ip [get_ips lcd_vio]
# 明确列出本顶层实际使用的文件，新增实验文件不会自动进入发布构建。
set sources {
 rtl/core/row_window3.sv rtl/core/gaussian3.sv rtl/core/sobel3.sv rtl/core/edge_core.sv
 rtl/camera/vsync_low_filter.sv rtl/camera/href_stable_filter.sv
 rtl/camera/ov7670_config.sv rtl/camera/camera_fifo_video.sv
 rtl/display/nt35510_bus8.sv rtl/display/nt35510_init_rom.sv
 rtl/display/nt35510_init.sv rtl/display/nt35510_window_writer.sv
 rtl/runtime/video_core_adapter.sv rtl/runtime/video_lcd_sink.sv
 rtl/runtime/capture_fault_latch.sv rtl/lcd_top.sv
}
if {$snapshot} {
 lappend sources rtl/debug/video_snapshot.sv rtl/debug/bars_monitor.sv
 lappend sources rtl/debug/uart_pair_stream.sv rtl/uart/uart_fast_tx.sv
}
foreach source $sources {read_verilog -sv [file join $root $source]}
read_xdc [file join $root constraints basys3_camera_lcd.xdc]
synth_design -top lcd_top -part xc7a35tcpg236-1 -generic STAT_FRAMES=$stat_frames
if {[llength [get_cells -hier -filter {REF_NAME =~ LD*}]]} {error "Unexpected latch"}
# Apply on actual synthesized IBUF cells; port-only assignment did not disable ZHOLD.
set camera_ibufs [get_cells -hier -filter {REF_NAME == IBUF && NAME =~ cam_data_IBUF*}]
if {[llength $camera_ibufs]!=8} {error "Expected8 camera input buffers"}
set_property IOBDELAY NONE $camera_ibufs
foreach c $camera_ibufs {puts "CAMERA_IBUF $c IOBDELAY=[get_property IOBDELAY $c]"}
write_checkpoint -force [file join $out post_synth.dcp]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $out post_route.dcp]
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $out timing.rpt]
report_drc -file [file join $out drc.rpt]
report_bus_skew -file [file join $out bus_skew.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
foreach delay {max min} {
 set paths [get_timing_paths -delay_type $delay -max_paths 1]
 if {![llength $paths] || [get_property SLACK $paths]<0} {error "Timing $delay failed"}
}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "Severe DRC"}
write_bitstream -force [file join $out $name.bit]
write_debug_probes -force [file join $out $name.ltx]
# 只写 OutDir；是否选用新产物，由下载入口的 ArtifactDir 明确指定。
puts "PASS LCD_V04_BUILD $name"
