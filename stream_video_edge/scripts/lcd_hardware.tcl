set root [file normalize [file join [file dirname [info script]] ..]]
set snapshot_mode [expr {[lsearch -exact $argv {-snapshot}]>=0}]
set argv [lsearch -all -inline -not -exact $argv {-snapshot}]
set probe_name [expr {$snapshot_mode?{lcd_top_snapshot}:{lcd_top}}]
set report_root [file join $root reports lcd runtime]
file mkdir $report_root
set action [lindex $argv 0]
if {$action ni {program one dump pause physical inspect}} {error "Unknown hardware action"}
open_hw_manager
connect_hw_server -url localhost:3121
try {
 set targets [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
 if {[llength $targets]!=1} {error "Expected Basys3 210183BCBF83A"}
 current_hw_target [lindex $targets 0];open_hw_target
 set dev [get_hw_devices xc7a35t_0]
 if {[llength $dev]!=1} {error "Expected XC7A35T"}
 current_hw_device $dev
 set_property PROBES.FILE [file join $root artifacts $probe_name.ltx] $dev
 if {$action eq {program}} {
  set variant [lindex $argv 1]
  if {$variant eq {}} {set variant $probe_name}
  if {$variant ni {lcd_top lcd_top_snapshot}} {error "Unknown program variant"}
  set_property PROBES.FILE [file join $root artifacts ${variant}.ltx] $dev
  set_property PROGRAM.FILE [file join $root artifacts ${variant}.bit] $dev
  program_hw_devices $dev
 }
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

 if {$action eq {one}} {
  set mode [lindex $argv 1];set label [lindex $argv 2]
  if {![string is integer -strict $mode] || $mode ni {0 1 4 5 8 9 12 13}} {error "Expected mode0/1/4/5/8/9/12/13"}
  if {![regexp {^[A-Za-z0-9_-]+$} $label]} {error "Unique evidence label required"}
  set path [file join $report_root [set label]_single.json]
  if {[file exists $path]} {error "Preserve existing capture"}
  drive 0 [expr {0x8000|$mode}];drive 1 1;wait_ready
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
  if {![llength [get_hw_probes -of_objects $vio -filter {TYPE == vio_input && PROBE_PORT == 11}]]} {error "Dump requires the optional -Snapshot build"}
  set s [status];set m [value 2];set snap [value 11]
  if {!($s&128)||!($s&32)||($s&24)||(($s>>8)&255)} {error "Pause a complete error-free frame before dump"}
  set n [expr {$m&0xffffffff}]
  if {$n==307200} {set w 640;set h 480} elseif {$n==296100} {set w 630;set h 470} else {error "Unexpected frame geometry"}
  set samples [expr {$w*$h/4}];set blocks [expr {($samples+127)/128}]
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
     refresh_hw_vio $vio;set ts [value 11]
     if {($ts>>29)!=0} {error "Snapshot error $ts"}
     if {(($ts>>20)&1)==$toggle && !(($ts>>19)&1)} {break}
     if {[clock milliseconds]>$limit} {error "Snapshot acknowledgement timeout"}
    }
    set hex {};for {set p 10} {$p>=3} {incr p -1} {append hex [widehex [value $p] 64]}
    puts $f "$b $hex"
    if {$b%100==0||$b==$blocks-1} {flush $f;puts "SNAPSHOT_READ $label [expr {$b+1}]/$blocks";flush stdout}
   }
  } finally {close $f}
  if {([status]>>16)!=$original_frame} {error "Frame changed while dumping"}
  set f [open [file join $report_root $label.json] w]
  puts $f "{\"label\":\"$label\",\"frame\":$original_frame,\"internal\":[expr {($s>>6)&1}],\"width\":[expr {$w/2}],\"height\":[expr {$h/2}],\"full_width\":$w,\"full_height\":$h,\"samples\":$samples,\"blocks\":$blocks,\"output_crc32\":[expr {($m>>64)&0xffffffff}],\"plane0\":\"display\",\"plane1\":\"same_frame_raw\"}"
  close $f
 } elseif {$action eq {physical}} {drive 1 0
 } elseif {$action eq {inspect}} {puts "INSPECT status=[status] metrics=[value 2] camera=[value 1]"
 } else {drive 0 0x8000;drive 1 1}
 puts "PASS LCD_CORE_$action"
} finally {catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}}
