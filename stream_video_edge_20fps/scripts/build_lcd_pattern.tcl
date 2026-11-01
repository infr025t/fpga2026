# 独立屏幕测试图入口：沿用当前发布版 LCD 接线，不包含摄像头或 VIO。
set root [file normalize [file join [file dirname [info script]] ..]]
set out [lindex $argv 0]
if {$out eq {}} {error "Usage: build_lcd_pattern.tcl OUT_DIR ?synth|bit?"}
set out [file normalize $out]
if {[string equal -nocase $out $root] || [string first [string tolower "${root}/"] [string tolower "${out}/"]]==0} {error "OutDir must be outside the source tree"}
set stage [lindex $argv 1]
if {$stage eq {}} {set stage bit}
if {$stage ni {synth bit}} {error "Expected synth or bit"}
file mkdir $out
create_project -force lcd_pattern [file join $out project] -part xc7a35tcpg236-1
foreach name {nt35510_bus8 nt35510_init_rom nt35510_init nt35510_window_writer nt35510_test_display nt35510_bringup_top} {
 read_verilog -sv [file join $root rtl display ${name}.sv]
}
# 从同一接线文件取屏幕/开关/LED约束，过滤不存在的摄像头和UART端口。
set input [open [file join $root constraints basys3_camera_lcd.xdc] r]
set constraints [read $input];close $input
set pattern_xdc [file join $out lcd_pattern.xdc]
set output [open $pattern_xdc w]
foreach line [split $constraints \n] {
 if {![regexp {cam_|camera/|uart_txd|fifo_virtual} $line]} {puts $output $line}
}
close $output
read_xdc $pattern_xdc
synth_design -top nt35510_bringup_top -part xc7a35tcpg236-1
if {[llength [get_cells -hier -filter {REF_NAME =~ LD*}]]} {error "Unexpected latch"}
write_checkpoint -force [file join $out post_synth.dcp]
report_utilization -file [file join $out utilization_synth.rpt]
if {$stage eq {bit}} {
 opt_design
 place_design
 phys_opt_design
 route_design
 write_checkpoint -force [file join $out post_route.dcp]
 report_timing_summary -report_unconstrained -file [file join $out timing.rpt]
 report_drc -file [file join $out drc.rpt]
 foreach delay {max min} {
  set paths [get_timing_paths -delay_type $delay -max_paths 1]
  if {![llength $paths] || [get_property SLACK $paths]<0} {error "Timing $delay failed"}
 }
 if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "Severe DRC"}
 write_bitstream -force [file join $out lcd_pattern.bit]
}
puts "PASS LCD_PATTERN_BUILD $stage"
