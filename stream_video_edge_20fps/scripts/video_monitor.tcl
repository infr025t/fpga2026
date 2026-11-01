source [file join [file dirname [info script]] hardware_common.tcl]
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
set_property PROBES.FILE [require_artifact $probe_name.ltx] $dev
refresh_hw_device $dev
set vio [get_hw_vios -of_objects $dev]
if {[llength $vio]!=1} {error "Expected one LCD VIO"}


set log [open [file join $folder frames.jsonl] w]
set last 0
set reason unknown
set started [clock milliseconds]
set final_perf 0
try {
 drive 0 [expr {0x8000|$mode}];drive 1 3;after 30;drive 1 1
 wait_ready
 set started [clock milliseconds]
 drive 0 $mode
 set limit [expr {$started+120000}]
 while {1} {
  set s [status];set p [value 3]
  set final_perf $p
  set err [expr {($s>>8)&255}]
  set frames [expr {($p>>160)&0xffffffff}]
  set period [expr {$p&0xffffffff}];set worst [expr {($p>>32)&0xffffffff}]
  if {$err || (($p>>224)&0xffffffff)!=0} {
   set reason FPGA_ERROR
   set f [open [file join $folder fault.json] w]
   puts $f "{\"status\":$s,\"error\":$err,\"performance\":$p,\"metrics\":[value 2],\"camera\":[value 1],\"bars_diagnostic\":[value 7]}"
   close $f;break
  }
  if {[file exists [file join $folder stop.flag]]} {set reason HOST_STOP;break}
  if {$frames!=$last && $frames>0} {
   set m [value 2];set c [value 1]
   set rx [expr {($m>>32)&0xffffffff}];set tx [expr {$m&0xffffffff}]
   set ci [expr {($m>>96)&0xffffffff}];set co [expr {($m>>64)&0xffffffff}]
   set n [expr {($mode&4)?296100:307200}]
   if {$rx!=$n || $tx!=$n || $ci!=$co} {set reason INTEGRITY_ERROR;break}
   if {($mode&1) || $mode==2 || $mode==6} {
    set expected [expr {($mode&1)?(($mode&4)?0x00032a9c:0xf9824a15):($mode==6?0x2c1f5efc:0x6df0b9b5)}]
    if {$ci!=$expected} {set reason REFERENCE_ERROR;break}
   }
   puts $log "{\"frames\":$frames,\"elapsed_ms\":[expr {[clock milliseconds]-$started}],\"period_ticks\":$period,\"worst_period_ticks\":$worst,\"sensor_period_ticks\":[expr {($p>>64)&0xffffffff}],\"sensor_frames\":[expr {($p>>96)&0xffffffff}],\"read_frames\":[expr {($p>>128)&0xffffffff}],\"max_occupancy\":[expr {($p>>192)&0xffffffff}],\"crc_in\":$ci,\"crc_out\":$co,\"pixels_in\":$rx,\"pixels_out\":$tx,\"min_href_ticks\":[expr {($c>>128)&0xffffffff}]}"
   flush $log
   if {$frames>=3 && ($period==0 || $worst>5000000)} {set reason FPS_BELOW_20;break}
   set last $frames
   if {$frames%25==0} {puts "VIDEO_PROGRESS frames=$frames fps=[expr {$period?100000000.0/$period:0}]";flush stdout}
   if {$max_records>0 && $frames>=$max_records} {set reason FRAME_TARGET;break}
  }
  if {[clock milliseconds]>$limit} {set reason TIMEOUT;break}
  after 5
 }
} finally {
 if {$reason ni {FRAME_TARGET HOST_STOP}} {
  catch {
   set f [open [file join $folder stop_context_before_pause.json] w]
   puts $f "{\"reason\":\"$reason\",\"status\":$s,\"performance\":$p,\"completed_metrics\":[value 2],\"camera\":[value 1],\"bars_diagnostic\":[value 7]}"
   close $f
  }
 }
 catch {drive 0 [expr {0x8000|$mode}]}
 after 100
 catch {
  set final_s [status]
  set final_perf [value 3]
  if {(($final_s>>8)&255)!=0 || (($final_perf>>224)&0xffffffff)!=0} {
   set reason FPGA_ERROR_AFTER_PAUSE
   set ff [open [file join $folder fault_after_pause.json] w]
   puts $ff "{\"status\":$final_s,\"performance\":$final_perf,\"metrics\":[value 2],\"camera\":[value 1],\"bars_diagnostic\":[value 7]}"
   close $ff
  }
 }
 catch {close $log}
 set f [open [file join $folder summary.json] w]
 set period [expr {$final_perf&0xffffffff}]
 set worst [expr {($final_perf>>32)&0xffffffff}]
 puts $f "{\"reason\":\"$reason\",\"mode\":$mode,\"frames\":$last,\"duration_ms\":[expr {[clock milliseconds]-$started}],\"period_ticks\":$period,\"worst_period_ticks\":$worst,\"performance\":$final_perf,\"fps\":[expr {$period?100000000.0/$period:0}]}"
 close $f
 catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
}
if {$reason ni {FRAME_TARGET HOST_STOP}} {error "Video check stopped: $reason"}
