set root [file normalize [file join [file dirname [info script]] ..]]
set snapshot_mode [expr {[lsearch -exact $argv {-snapshot}]>=0}]
set argv [lsearch -all -inline -not -exact $argv {-snapshot}]
set probe_name [expr {$snapshot_mode?{lcd_top_snapshot}:{lcd_top}}]
set report_root [file join $root reports lcd runtime]
file mkdir $report_root
set label [lindex $argv 0]
set mode [lindex $argv 1]
set max_records [lindex $argv 2]
if {$max_records eq {}} {set max_records 0}
if {![string is integer -strict $max_records] || $max_records<0} {error "Invalid optional record limit"}
if {$mode ni {0 1 2 4 5 6}} {error "mode0 scene RAW,1 internal RAW,2 sensor bars RAW,4 scene EDGE,5 internal EDGE,6 sensor bars EDGE"}
set expected_pixels [expr {($mode&4)?296100:307200}]
if {![regexp {^[A-Za-z0-9_-]+$} $label]} {error "Specify a unique label"}
set folder [file join $report_root $label]
if {[file exists $folder]} {error "Preserve previous run"}
file mkdir $folder
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
if {[llength $targets]!=1} {error "Expected task Basys3"}
current_hw_target [lindex $targets 0];open_hw_target
set dev [get_hw_devices xc7a35t_0]
set_property PROBES.FILE [file join $root artifacts $probe_name.ltx] $dev
refresh_hw_device $dev
set vio [get_hw_vios -of_objects $dev]
if {[llength $vio]!=1} {error "Expected one LCD VIO"}
 proc drive {port value} {
  global vio
  set p [get_hw_probes -of_objects $vio -filter "TYPE == vio_output && PROBE_PORT == $port"]
  if {[llength $p]!=1} {error "Expected one complete output probe on port $port"}
  set_property OUTPUT_VALUE_RADIX HEX $p
  set_property OUTPUT_VALUE [format %0*x [expr {([get_property WIDTH $p]+3)/4}] $value] $p
  commit_hw_vio $p
 }
 proc value {port} {
  global vio
  set result 0
  foreach p [get_hw_probes -of_objects $vio -filter "TYPE == vio_input && PROBE_PORT == $port"] {
   set bits [regexp -all -inline {[0-9]+} [get_property PROBE_PORT_BITS $p]]
   set low [lindex [lsort -integer $bits] 0]
   set_property INPUT_VALUE_RADIX HEX $p
   set part [expr "0x[get_property INPUT_VALUE $p]"]
   set result [expr {$result | ($part<<$low)}]
  }
  return $result
 }
 proc status {} {global vio;refresh_hw_vio $vio;return [value 0]}
 proc wait_ready {} {
  set limit [expr {[clock milliseconds]+15000}]
  while {1} {
   set s [status]
   if {(($s>>8)&255)!=0} {error [format "FPGA error status=%08x" $s]}
   if {$s&1} {return $s}
   if {[clock milliseconds]>$limit} {error [format "Readiness timeout status=%08x" $s]}
   after 40
  }
 }


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
