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


set log [open [file join $folder frames.jsonl] w]
set started [clock milliseconds];set previous 0;set last 0;set records 0;set gaps 0;set reason UNKNOWN;set control physical
try {
 drive 0 0x8000;drive 1 3;after 30;drive 1 1;wait_ready
 drive 0 0;after 200
 # Give physical SW15 ownership if physical source/mode is the requested RAW.
 drive 1 0;after 300
 set s [status];set m [value 2]
 if {($s&192)!=0 || ($m&0xffffffff)!=307200} {
  set control JTAG_RAW_OVERRIDE
  drive 0 0;drive 1 1;after 200
 }
 set last [expr {([value 3]>>160)&0xffffffff}];set previous $last
 puts "DYNAMIC_LIVE_STARTED mode=CAMERA_RAW control=$control; continuous until BTNC or stop.flag"
 flush stdout
 while {1} {
  set s [status];set p [value 3];set m [value 2];set c [value 1]
  set frame [expr {($p>>160)&0xffffffff}]
  if {($s&2)==0 || $frame<$previous} {set reason USER_RESET;break}
  if {(($s>>8)&255)!=0} {
   set reason FPGA_ERROR
   set f [open [file join $folder fault.json] w]
   puts $f "{\"status\":$s,\"performance\":$p,\"metrics\":$m,\"camera\":$c}";close $f;break
  }
  if {[file exists [file join $folder stop.flag]]} {set reason HOST_STOP;break}
  if {$frame!=$last} {
   if {$frame>$last+1} {incr gaps [expr {$frame-$last-1}]}
   incr records
   set n [expr {($m>>32)&0xffffffff}];set painted [expr {$m&0xffffffff}]
   set ci [expr {($m>>96)&0xffffffff}];set co [expr {($m>>64)&0xffffffff}]
   puts $log "{\"frame\":$frame,\"elapsed_ms\":[expr {[clock milliseconds]-$started}],\"period_ticks\":[expr {$p&0xffffffff}],\"pixels_in\":$n,\"pixels_out\":$painted,\"crc_in\":$ci,\"crc_out\":$co,\"camera\":$c,\"status\":$s}"
   flush $log
   if {$n!=$painted || $ci!=$co} {set reason INTEGRITY_ERROR;break}
   if {$frame%250==0 || $records==1} {puts "LIVE frame=$frame pixels=$n fps=[expr {($p&0xffffffff)?100000000.0/($p&0xffffffff):0}]";flush stdout}
   set last $frame
  }
  set previous $frame
  after 5
 }
} finally {
 catch {drive 0 0x8000;drive 1 1};after 100
 catch {close $log}
 set f [open [file join $folder summary.json] w]
 puts $f "{\"reason\":\"$reason\",\"records\":$records,\"last_frame\":$last,\"host_gaps\":$gaps,\"control\":\"$control\",\"duration_ms\":[expr {[clock milliseconds]-$started}],\"image_quality\":\"scene images have no known CRC reference; data/count monitoring cannot replace screen observation\"}"
 close $f
 catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
}
