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
if {$mode ni {0 4}} {error "Specify camera mode0 RAW,4 Gaussian EDGE"}
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
set log [open [file join $folder frames.jsonl] w]
set started [clock milliseconds]
set last -1
set records 0
set gaps 0
set reason unknown
try {
 drive 0 [expr {0x8000|$mode}];drive 1 1
 wait_ready
 set previous [expr {[status]>>16}]
 set last $previous
 drive 0 $mode
 puts "STABILITY_STARTED label=$label initial_frame=$previous; BTNC stops this run"
 flush stdout
 while {1} {
  set s [status]
  set frame [expr {$s>>16}]
  set err [expr {($s>>8)&255}]
  if {($frame<$previous && !($previous==65535 && ($s&2))) || !($s&2)} {
   set reason USER_RESET_DETECTED
   drive 0 [expr {0x8000|$mode}]
   puts "STABILITY_STOP $reason";flush stdout
   break
  }
  if {[file exists [file join $folder stop.flag]]} {set reason HOST_STOP;drive 0 [expr {0x8000|$mode}];break}
  if {$err} {
   set reason FPGA_ERROR
   drive 0 [expr {0x8000|$mode}]
   set f [open [file join $folder fault.json] w]
   puts $f "{\"status\":$s,\"error\":$err,\"metrics\":[value 2],\"camera\":[value 1]}"
   close $f
   puts "STABILITY_STOP $reason code=$err";flush stdout
   break
  }
  if {($s&32) && !($s&24) && !($s&64) && $frame!=$last} {
   set m [value 2];set c [value 1]
   set rx [expr {($m>>32)&0xffffffff}];set tx [expr {$m&0xffffffff}]
   set ci [expr {($m>>96)&0xffffffff}];set co [expr {($m>>64)&0xffffffff}]
   if {$last>=0} {
    set delta [expr {($frame-$last+65536)%65536}]
    if {$delta>1} {incr gaps [expr {$delta-1}]}
   }
   set line "{\"frame\":$frame,\"elapsed_ms\":[expr {[clock milliseconds]-$started}],\"source_pixels\":$rx,\"display_pixels\":$tx,\"input_crc32\":$ci,\"output_crc32\":$co,\"rows\":[expr {$c&0xffffffff}],\"read_bytes\":[expr {($c>>32)&0xffffffff}],\"min_href\":[expr {($c>>128)&0xffffffff}],\"max_href\":[expr {($c>>160)&0xffffffff}],\"unlogged_frame_count\":$gaps}"
   puts $log $line;flush $log
   incr records;set last $frame
   if {$rx!=$expected_pixels || $tx!=$expected_pixels || $ci!=$co || ($c&0xffffffff)!=480 || (($c>>32)&0xffffffff)!=614400} {
    set reason INTEGRITY_ERROR;drive 0 [expr {0x8000|$mode}]
    puts "STABILITY_STOP $reason";flush stdout;break
   }
   if {$max_records>0 && $records>=$max_records} {set reason RECORDED_FRAME_LIMIT;drive 0 [expr {0x8000|$mode}];break}
   if {$records%10==0} {puts "STABILITY_PROGRESS records=$records frame=$frame gaps=$gaps";flush stdout}
  }
  set previous $frame
  after 20
 }
} finally {
 catch {drive 0 [expr {0x8000|$mode}]}
 catch {close $log}
 set f [open [file join $folder summary.json] w]
 puts $f "{\"reason\":\"$reason\",\"records\":$records,\"last_logged_frame\":$last,\"unlogged_frame_count\":$gaps,\"duration_ms\":[expr {[clock milliseconds]-$started}],\"image_review\":\"host counters and CRC; no automated glass review or per-frame export\"}"
 close $f
 catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
}

# Automation must not mistake a recorded fault or premature reset for a passing run.
if {$reason in {FPGA_ERROR INTEGRITY_ERROR unknown} || ($max_records>0 && $reason ne {RECORDED_FRAME_LIMIT})} {
 error "LCD live check did not pass: $reason"
}
