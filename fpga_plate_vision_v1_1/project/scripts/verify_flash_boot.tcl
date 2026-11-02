# 按JP1所选模式重新启动，不通过JTAG下载业务bit；失败时恢复已验证RAM程序。
set root [file normalize [file join [file dirname [info script]] ..]]
set artifacts [file normalize [file join $root .. release]]
if {[llength $argv]} {set artifacts [file normalize [lindex $argv 0]]}
set dev {};set boot_started 0;set verified 0
try {
 open_hw_manager
 connect_hw_server -url localhost:3121
 set targets [get_hw_targets -quiet -filter {NAME =~ *210183BCBF83A}]
 if {[llength $targets]!=1} {error "Expected Basys3 210183BCBF83A"}
 current_hw_target [lindex $targets 0];open_hw_target
 set dev [get_hw_devices xc7a35t_0]
 if {[llength $dev]!=1} {error "Expected XC7A35T"}
 current_hw_device $dev
 set boot_started 1
 # Vivado 2025.1 的返回文本另行记录；真正验收使用重新加载后的 VIO 和帧计数。
 set boot_result [boot_hw_device -timeout 30 $dev]
 puts "FLASH_BOOT_COMMAND_RESULT <$boot_result>"
 set_property PROBES.FILE [file join $artifacts autonomous_board.ltx] $dev
 after 3000
 refresh_hw_device $dev
 set vio [get_hw_vios -of_objects $dev]
 if {[llength $vio]!=1} {error "No expected VIO after boot"}
 set status [get_hw_probes -of_objects $vio -filter {TYPE == vio_input && PROBE_PORT == 0}]
 if {[llength $status]!=1} {error "No system status after boot"}
 set_property INPUT_VALUE_RADIX HEX $status
 refresh_hw_vio $vio
 scan [get_property INPUT_VALUE $status] %x first
 after 1500
 refresh_hw_vio $vio
 scan [get_property INPUT_VALUE $status] %x second
 set delta [expr {(($second>>16)-($first>>16))&0xffff}]
 set fault [expr {($second>>8)&0xff}]
 puts [format "FLASH_BOOT_STATUS first=%08x second=%08x frames_advanced=%d error=%02x" $first $second $delta $fault]
 if {$delta<=0 || $fault!=0} {error "Video is not advancing normally after boot"}
 set verified 1
 puts "PASS FLASH_RELOAD_AND_VIDEO_RUNNING"
} finally {
 try {
  if {$boot_started && !$verified} {
   set_property PROGRAM.FILE [file join $artifacts autonomous_board.bit] $dev
   set_property PROBES.FILE [file join $artifacts autonomous_board.ltx] $dev
   program_hw_devices $dev
   puts "RESTORED_RAM_AFTER_BOOT_CHECK_FAILURE"
  }
 } finally {
  catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
 }
}
