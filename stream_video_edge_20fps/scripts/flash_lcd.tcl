# Basys3 4 MiB SPI Flash：复用已验证流程，保留器件 ID 检查和失败后的 RAM 恢复。
if {[llength $argv]!=6} {error "Usage: flash_lcd.tcl prepare|backup|program ARTIFACT_DIR OUT_DIR RESTORE_DIR PART TARGET_SERIAL"}
lassign $argv action artifact_dir out restore_dir part serial
if {$action ni {prepare backup program}} {error "Expected prepare, backup or program"}
if {![regexp {^[A-Za-z0-9]+$} $serial]} {error "Invalid exact target serial"}
if {![regexp {^[A-Za-z0-9_-]+$} $part]} {error "Specify an exact cfgmem part name"}
foreach name {artifact_dir out restore_dir} {set $name [file normalize [set $name]]}
set bit [file join $artifact_dir lcd_top_snapshot.bit]
set restore_bit [file join $restore_dir lcd_top_snapshot.bit]
set restore_ltx [file join $restore_dir lcd_top_snapshot.ltx]
set mcs [file join $out lcd_top_snapshot.mcs]
set backup [file join $out flash_before.bin]
proc need_file {path} {if {![file isfile $path]} {error "Missing file: $path"}}
need_file $bit
file mkdir $out
if {$action ne {prepare}} {
 need_file $restore_bit;need_file $restore_ltx
 if {$action eq {backup} && [file exists $backup]} {error "Preserve existing Flash backup: $backup"}
 if {$action eq {program}} {
  need_file $backup
  if {[file size $backup]!=4194304} {error "Complete 4 MiB Flash backup required"}
 }
}
if {$action in {prepare program}} {
 # 只转换输入 bit，不改写它；program 重新生成 MCS，避免使用过期镜像。
 write_cfgmem -force -format mcs -size 4 -interface SPIx1 -loadbit [list up 0x00000000 $bit] -file $mcs
 puts "PASS FLASH_MCS_READY $mcs"
}
if {$action eq {prepare}} {return}
set dev {};set ram_touched 0
try {
 open_hw_manager
 connect_hw_server -url localhost:3121
 set targets [get_hw_targets -quiet -filter "NAME =~ *$serial"]
 if {[llength $targets]!=1} {error "Expected one Basys3 target $serial"}
 current_hw_target [lindex $targets 0];open_hw_target
 set dev [get_hw_devices xc7a35t_0]
 if {[llength $dev]!=1} {error "Expected XC7A35T"}
 current_hw_device $dev
 set parts [get_cfgmem_parts $part]
 if {![llength $parts]} {error "Unsupported cfgmem part $part"}
 create_hw_cfgmem -hw_device $dev [lindex $parts 0]
 set mem [get_property PROGRAM.HW_CFGMEM $dev]
 set_property PROGRAM.UNUSED_PIN_TERMINATION pull-none $mem
 foreach flag {ERASE BLANK_CHECK CFG_PROGRAM VERIFY CHECKSUM} {set_property PROGRAM.$flag 0 $mem}
 if {$action eq {backup}} {
  set_property PROGRAM.ADDRESS_RANGE entire_device $mem
 } else {
  set_property PROGRAM.ADDRESS_RANGE use_file $mem
  set_property PROGRAM.FILES [list $mcs] $mem
  set_property PROGRAM.PRM_FILE [file join $out lcd_top_snapshot.prm] $mem
  foreach flag {ERASE BLANK_CHECK CFG_PROGRAM VERIFY} {set_property PROGRAM.$flag 1 $mem}
 }
 create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
 set ram_touched 1
 program_hw_devices $dev
 # 不传任何跳过 ID 检查的选项；Vivado 按指定 part 核对 JEDEC ID 后才操作 Flash。
 if {$action eq {backup}} {
  readback_hw_cfgmem -all -format bin -file $backup -hw_cfgmem $mem
  if {[file size $backup]!=4194304} {error "Incomplete Flash readback"}
  puts "PASS FLASH_BACKUP $part"
 } else {
  program_hw_cfgmem -hw_cfgmem $mem
  puts "PASS FLASH_PROGRAM_AND_VERIFY $part"
 }
} finally {
 # 嵌套 finally 确保恢复失败时也关闭连接；恢复错误不会被吞掉。
 try {
  if {$ram_touched} {
   set_property PROGRAM.FILE $restore_bit $dev
   set_property PROBES.FILE $restore_ltx $dev
   program_hw_devices $dev
   refresh_hw_device $dev
   puts "PASS RESTORED_TESTED_FPGA"
  }
 } finally {
  catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
 }
}
