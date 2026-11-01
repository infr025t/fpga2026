source [file join [file dirname [info script]] hardware_common.tcl]
set report_root [file join $root reports lcd runtime]
file mkdir $report_root
set action [lindex $argv 0]
if {$action ni {program reset one dump pause physical inspect resume}} {error "Expected program/reset/one/dump/pause/physical/inspect"}
# 显式下载型号决定 bit/ltx 配对，不先检查默认 Snapshot 的文件。
if {$action eq {program}} {
 set variant [lindex $argv 1]
 if {$variant eq {}} {set variant $probe_name}
 if {$variant ni {lcd_top lcd_top_snapshot}} {error "Unknown program variant"}
 set probe_file [require_artifact ${variant}.ltx]
 set program_file [require_artifact ${variant}.bit]
} else {
 set probe_file [require_artifact $probe_name.ltx]
}
open_hw_manager
connect_hw_server -url localhost:3121
try {
 set targets [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
 if {[llength $targets]!=1} {error "Expected Basys3 210183BCBF83A"}
 current_hw_target [lindex $targets 0];open_hw_target
 set dev [get_hw_devices xc7a35t_0]
 if {[llength $dev]!=1} {error "Expected XC7A35T"}
 current_hw_device $dev
 set_property PROBES.FILE $probe_file $dev
 if {$action eq {program}} {
  set_property PROGRAM.FILE $program_file $dev
  program_hw_devices $dev
 }
 refresh_hw_device $dev
 set vio [get_hw_vios -of_objects $dev]
 if {[llength $vio]!=1} {error "Expected one LCD VIO"}


 if {$action eq {reset}} {
  set mode [lindex $argv 1]
  if {$mode ni {0 1 2 4 5 6}} {error "Invalid video mode"}
  drive 0 [expr {0x8000|$mode}];drive 1 3;after 30;drive 1 1;wait_ready
 } elseif {$action eq {one}} {
  set mode [lindex $argv 1];set label [lindex $argv 2]
  if {![string is integer -strict $mode] || $mode ni {0 1 2 4 5 6}} {error "Expected mode 0/1/2/4/5/6"}
  if {![regexp {^[A-Za-z0-9_-]+$} $label]} {error "Unique evidence label required"}
  set path [file join $report_root [set label]_single.json]
  if {[file exists $path]} {error "Preserve existing capture"}
  drive 0 [expr {0x8000|$mode}];drive 1 3;after 30;drive 1 1;wait_ready
  set before [expr {[status]>>16}]
  drive 0 $mode
  set limit [expr {[clock milliseconds]+12000}]
  while {1} {
   set s [status]
   if {(($s>>8)&255)!=0} {error [format "FPGA error %08x" $s]}
   if {$s&16} {break}
   if {[clock milliseconds]>$limit} {error "Frame start timeout"};after 10
  }
  drive 0 [expr {0x8000|$mode}]
  while {1} {
   set s [status]
   if {(($s>>8)&255)!=0} {error [format "FPGA error %08x" $s]}
   if {($s&1) && ($s>>16)>$before} {break}
   if {[clock milliseconds]>$limit} {error "Completion timeout"};after 15
  }
  set m [value 2];set c [value 1]
  set rx [expr {($m>>32)&0xffffffff}];set tx [expr {$m&0xffffffff}]
  set ci [expr {($m>>96)&0xffffffff}];set co [expr {($m>>64)&0xffffffff}]
  set n [expr {($mode&4)?296100:307200}]
  if {$rx!=$n || $tx!=$n || $ci!=$co} {error "Full output count/CRC mismatch"}
  if {!($mode&1) && (($c&0xffffffff)!=480 || (($c>>32)&0xffffffff)!=614400)} {error "Camera counters failed"}
  if {$mode==2 && $ci!=0x6df0b9b5} {error "Sensor complete RAW reference mismatch"}
  if {$mode&1} {
   set expected [lindex $argv 3]
   if {![string is integer -strict $expected] || $ci!=$expected} {error "Internal complete-core reference mismatch"}
  }
  set f [open $path w]
  puts $f "{\"label\":\"$label\",\"mode\":$mode,\"frame\":[expr {$s>>16}],\"received\":$rx,\"painted\":$tx,\"input_crc32\":$ci,\"output_crc32\":$co,\"camera\":$c}"
  close $f;puts "PASS LCD_CORE_SINGLE $label pixels=$n crc=[format %08x $ci]"
 } elseif {$action eq {dump}} {
  set label [lindex $argv 1]
  if {![regexp {^[A-Za-z0-9_-]+$} $label]} {error "Unique evidence label required"}
  if {![llength [get_hw_probes -of_objects $vio -filter {TYPE == vio_input && PROBE_PORT == 6}]]} {error "Dump requires the optional -Snapshot build"}
  set s [status];set m [value 2];set snap [value 6]
  if {!($s&128)||!($s&32)||($s&24)} {error "Pause a complete error-free frame before dump"}
  set n [expr {$m&0xffffffff}]
  if {$n==307200} {set w 640;set h 480} elseif {$n==296100} {set w 630;set h 470} else {error "Unexpected frame geometry"}
  set samples [expr {($w/4)*(($h+3)/4)}];set blocks [expr {($samples+31)/32}]
  if {($snap>>29)!=0 || !($snap&131072) || ($snap&131071)!=$samples} {error "Snapshot incomplete $snap"}
  set original_frame [expr {$s>>16}]
  set path [file join $report_root $label.blocks.txt]
  if {[file exists $path]} {error "Preserve previous snapshot"}
  set f [open $path w]
  set toggle [expr {($snap>>20)&1}]
  proc widehex {v digits} {
   set text {};for {set i 0} {$i<$digits} {incr i} {set text "[format %x [expr {$v&15}]]$text";set v [expr {$v>>4}]};return $text
  }
  try {
   for {set b 0} {$b<$blocks} {incr b} {
    set toggle [expr {!$toggle}];drive 2 [expr {($toggle<<10)|$b}]
    set limit [expr {[clock milliseconds]+3000}]
    while {1} {
     refresh_hw_vio $vio;set ts [value 6]
     if {($ts>>29)!=0} {error "Snapshot error $ts"}
     if {(($ts>>20)&1)==$toggle && !(($ts>>19)&1)} {break}
     if {[clock milliseconds]>$limit} {error "Snapshot acknowledgement timeout"}
    }
    set hex {};for {set p 5} {$p>=4} {incr p -1} {append hex [widehex [value $p] 64]}
    puts $f "$b $hex"
    if {$b%100==0||$b==$blocks-1} {flush $f;puts "SNAPSHOT_READ $label [expr {$b+1}]/$blocks";flush stdout}
   }
  } finally {close $f}
  if {([status]>>16)!=$original_frame} {error "Frame changed while dumping"}
  set f [open [file join $report_root $label.json] w]
  puts $f "{\"label\":\"$label\",\"frame\":$original_frame,\"internal\":[expr {($s>>6)&1}],\"width\":[expr {$w/4}],\"height\":[expr {($h+3)/4}],\"full_width\":$w,\"full_height\":$h,\"samples\":$samples,\"blocks\":$blocks,\"roi\":false,\"overview\":true,\"stride\":4,\"sample_x\":3,\"sample_y\":0,\"block_words\":32,\"roi_x\":0,\"roi_y\":0,\"output_crc32\":[expr {($m>>64)&0xffffffff}],\"plane0\":\"display\",\"plane1\":\"[expr {($s&64)||$w==630?{same_frame_raw}:{preceding_fifo_byte}}]\"}"
  close $f
 } elseif {$action eq {resume}} {
  set mode [lindex $argv 1]
  if {$mode ni {0 1 2 4 5 6}} {error "Invalid video mode"}
  drive 0 [expr {0x8000|$mode}];drive 1 1;wait_ready;drive 0 $mode
 } elseif {$action eq {physical}} {drive 1 0
 } elseif {$action eq {inspect}} {puts "INSPECT status=[status] metrics=[value 2] camera=[value 1] performance=[value 3] bars=[value 7]"
 } else {drive 0 0x8000;drive 1 1}
 puts "PASS LCD_CORE_$action"
} finally {catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}}
