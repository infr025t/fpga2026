source [file join [file dirname [info script]] hardware_common.tcl]
set report_root [file join $root reports lcd runtime]
file mkdir $report_root
set label [lindex $argv 0]
set mode [lindex $argv 1]
set max_records [lindex $argv 2]
# 帧数必须与 build_lcd.ps1 -StatFrames 一致；缺省保留 2500 帧检查。
if {$max_records eq {}} {set max_records 2500}
if {![string is integer -strict $max_records] || $max_records<=0} {error "Expected positive target frame count"}
if {$mode ne {2}} {error "Statistics requires mode 2: sensor bars RAW"}
if {!$snapshot_mode} {error "Statistics requires the full Snapshot build"}
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
set reason UNKNOWN;set last 0;set polls 0;set skipped 0;set first_bad -1;set last_bad -1;set p 0;set s 0;set previous_bad 0
set started [clock milliseconds]
try {
 drive 0 0x8002;drive 1 3;after 30;drive 1 1;wait_ready
 set started [clock milliseconds];set deadline [expr {$started+max(300000,$max_records*100+30000)}]
 drive 0 2
 while {1} {
  set s [status];set p [value 3];set m [value 2];set c [value 1]
  set frames [expr {($p>>160)&0xffffffff}]
  set bad [expr {$p>>224}]
  set period [expr {$p&0xffffffff}]
  if {(($s>>8)&255)!=0} {set reason FPGA_FATAL_ERROR;break}
  if {$frames!=$last} {
   incr polls
   if {$frames>$last+1} {incr skipped [expr {$frames-$last-1}]}
   if {$bad>$previous_bad} {
    if {$first_bad<0} {set first_bad $frames}
    set last_bad $frames
   }
   puts $log "{\"frame\":$frames,\"cumulative_bad_frames\":$bad,\"period_ticks\":$period,\"elapsed_ms\":[expr {[clock milliseconds]-$started}],\"crc32\":[expr {($m>>96)&0xffffffff}],\"pixels_in\":[expr {($m>>32)&0xffffffff}],\"pixels_out\":[expr {$m&0xffffffff}],\"camera\":$c,\"bars_diagnostic\":[value 7]}"
   flush $log
   if {$frames%100==0 || $bad!=$previous_bad} {puts "STATS frames=$frames bad=$bad fps=[expr {$period?100000000.0/$period:0}]";flush stdout}
   set last $frames;set previous_bad $bad
  }
  if {$frames==$max_records && !($s&24)} {set reason COMPLETE;break}
  if {$frames>$max_records} {set reason TARGET_OVERRUN;break}
  if {[clock milliseconds]>$deadline} {set reason TIMEOUT;break}
  after 5
 }
} finally {
 catch {drive 0 0x8002};after 100
 catch {set s [status];set p [value 3];set m [value 2];set c [value 1]}
 set frames [expr {($p>>160)&0xffffffff}];set bad [expr {$p>>224}]
 set period [expr {$p&0xffffffff}]
 if {(($s>>8)&255)!=0} {set reason FPGA_FATAL_ERROR}
 if {$frames!=$max_records && $reason eq {COMPLETE}} {set reason INCOMPLETE}
 set f [open [file join $folder summary.json] w]
 puts $f "{\"reason\":\"$reason\",\"requested_frames\":$max_records,\"completed_frames\":$frames,\"bad_frames\":$bad,\"good_frames\":[expr {$frames-$bad}],\"error_rate\":[expr {$frames?double($bad)/$frames:0}],\"duration_ms\":[expr {[clock milliseconds]-$started}],\"period_ticks\":$period,\"fps\":[expr {$period?100000000.0/$period:0}],\"host_records\":$polls,\"host_skipped_frames\":$skipped,\"first_bad_observed_frame\":$first_bad,\"last_bad_observed_frame\":$last_bad,\"fpga_status\":$s,\"performance\":$p,\"metrics\":$m,\"camera\":$c,\"basis\":\"FPGA full-frame CRC counter; sample image not used to estimate bad count\"}"
 close $f;close $log
 puts "STATS_RESULT reason=$reason total=$frames bad=$bad good=[expr {$frames-$bad}]"
 catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
}
if {$reason ne {COMPLETE}} {error "Incomplete statistics test: $reason"}
