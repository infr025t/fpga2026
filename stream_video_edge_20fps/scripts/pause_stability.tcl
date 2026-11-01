source [file join [file dirname [info script]] hardware_common.tcl]
set label [lindex $argv 0]
set mode [lindex $argv 1]
set max_records [lindex $argv 2]
# 此检查使用传感器色条的固定 CRC；必须实际执行至少一轮暂停/恢复。
if {$max_records eq {}} {set max_records 10}
if {![string is integer -strict $max_records] || $max_records<=0} {error "Expected positive pause round count"}
if {$mode ne {2}} {error "Pause stability requires mode 2: sensor bars RAW"}
if {![regexp {^[A-Za-z0-9_-]+$} $label]} {error "Specify a unique label"}
set report_root [file join $root reports lcd runtime]
file mkdir $report_root
set folder [file join $report_root $label]
if {[file exists $folder]} {error "Preserve previous run"}
file mkdir $folder
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
if {[llength $targets]!=1} {error "Expected task Basys3"}
current_hw_target [lindex $targets 0];open_hw_target
set dev [get_hw_devices xc7a35t_0]
set_property PROBES.FILE [require_artifact $probe_name.ltx] $dev
refresh_hw_device $dev
set vio [get_hw_vios -of_objects $dev]
if {[llength $vio]!=1} {error "Expected one LCD VIO"}



set log [open [file join $folder epochs.jsonl] w]
try {
 drive 0 0x8002;drive 1 3;after 30;drive 1 1;wait_ready
 for {set epoch 0} {$epoch<$max_records} {incr epoch} {
  set before [expr {([value 3]>>160)&0xffffffff}]
  drive 0 2
  set limit [expr {[clock milliseconds]+10000}]
  while {1} {
   set s [status];set perf [value 3];set m [value 2]
   if {(($s>>8)&255) || ($perf>>224)!=0} {error "Epoch $epoch FPGA failure status=$s metrics=$m"}
   set frames [expr {($perf>>160)&0xffffffff}]
   if {$frames>=$before+10} {break}
   if {[clock milliseconds]>$limit} {error "Epoch capture timeout"}
   after 5
  }
  set period [expr {$perf&0xffffffff}]
  if {$period==0 || $period>5000000} {error "Epoch fps below20"}
  drive 0 0x8002
  while {1} {
   set s [status]
   if {(($s>>8)&255)} {error "Pause failure status=$s"}
   if {($s&128)&&($s&32)&&!($s&24)} {break}
   if {[clock milliseconds]>$limit} {error "Pause drain timeout"}
   after 5
  }
  set perf [value 3];set m [value 2]
  if {(($m>>96)&0xffffffff)!=0x6df0b9b5 || (($m>>64)&0xffffffff)!=0x6df0b9b5 || ($m&0xffffffff)!=307200} {error "Epoch CRC/count mismatch"}
  puts $log "{\"epoch\":$epoch,\"completed_frames\":[expr {($perf>>160)&0xffffffff}],\"period_ticks\":$period,\"crc32\":[expr {($m>>96)&0xffffffff}],\"reference_failures\":[expr {$perf>>224}]}"
  flush $log;puts "VIDEO_EPOCH $epoch passed"
 }
 puts "PASS VIDEO_EPOCHS $max_records"
} finally {
 catch {
  set f [open [file join $folder final_context.json] w]
  puts $f "{\"status\":[status],\"performance\":[value 3],\"metrics\":[value 2],\"camera\":[value 1],\"bars\":[value 7]}"
  close $f
 }
 catch {drive 0 0x8002};catch {close $log}
 catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
}
