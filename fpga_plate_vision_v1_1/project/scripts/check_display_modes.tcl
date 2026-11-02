# 实机模式烟雾检查：只使用通用VIO控制，不改Flash或相机参数。
# 每种模式等一秒完成排空/清屏，读取两次帧指标；外层解析器再校验计数和CRC。
set script_root [file dirname [info script]]
set build_dir [file normalize [file join $script_root .. .. release]]
if {[llength $argv]} {set build_dir [file normalize [lindex $argv 0]]}
foreach mode_name {raw edge internal auto} {
 puts "MODE_BEGIN $mode_name"
 set argv [list $mode_name $build_dir]
 source [file join $script_root hardware.tcl]
 after 1000
 foreach sample_id {1 2} {
  puts "MODE_SAMPLE $mode_name $sample_id"
  set argv [list status $build_dir]
  source [file join $script_root hardware.tcl]
  after 1000
 }
 puts "MODE_END $mode_name"
}
puts "MODE_SEQUENCE_DONE auto remains enabled for passive OCR observation"
