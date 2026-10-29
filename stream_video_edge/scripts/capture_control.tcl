set root [file normalize [file join [file dirname [info script]] ..]]
set folder [file normalize [lindex $argv 0]]
set diagnostic_ltx [file join $root artifacts edge_top.ltx]
set count [lindex $argv 1]
set pattern [lindex $argv 2]
set threshold [lindex $argv 3]
if {![string is integer -strict $count] || $count<1 || $count>100} {error "Invalid count"}
if {$pattern ni {0 1} || ![string is integer -strict $threshold] || $threshold<0 || $threshold>2040 || $threshold%4} {error "Invalid source/threshold"}
proc cancelled {} {global folder;if {[file exists [file join $folder abort.flag]]} {error "PC capture stopped"}}
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
if {[llength $targets]!=1} {error "Expected task Basys3 only"}
current_hw_target [lindex $targets 0]
open_hw_target
try {
 set dev [get_hw_devices xc7a35t_0]
 set_property PROBES.FILE $diagnostic_ltx $dev
 refresh_hw_device $dev
 set vio [get_hw_vios -of_objects $dev]
 if {[llength $vio]!=1} {error "Expected one VIO"}
 proc probe {name} {global vio;set p [get_hw_probes $name -of_objects $vio];if {[llength $p]!=1} {error "Missing VIO probe $name"};return $p}
 proc drive {name value} {set p [probe $name];set_property OUTPUT_VALUE_RADIX HEX $p;set_property OUTPUT_VALUE $value $p;commit_hw_vio $p}
 proc value {name} {set p [probe $name];set_property INPUT_VALUE_RADIX HEX $p;scan [get_property INPUT_VALUE $p] %x n;return $n}
 set base [expr {$pattern|(($threshold/4)<<4)}]
 drive virtual_sw [format %04x $base]
 drive debug_control 3
 after 50
 drive debug_control 1
 set limit [expr {[clock milliseconds]+20000}]
 while {1} {
  cancelled;refresh_hw_vio $vio
  if {[value ready]} {break}
  if {[clock milliseconds]>$limit} {error "Ready timeout"}
  after 40
 }
 puts "EDGE_READY";flush stdout
 for {set saved 0} {$saved<$count} {incr saved} {
  cancelled
  set m [expr {$saved%4}]
  set switches [expr {$base|(($m/2)<<2)|(($m%2)<<1)}]
  drive virtual_sw [format %04x $switches]
  after 50
  drive virtual_sw [format %04x [expr {$switches|0x8000}]]
  after 50
  drive virtual_sw [format %04x $switches]
  set limit [expr {[clock milliseconds]+30000}]
  set last_rejected_pulses 0
  set signal_probe [get_hw_probes -quiet debug_sync -of_objects $vio]
  if {[llength $signal_probe]} {set_property INPUT_VALUE_RADIX HEX $signal_probe}
  while {1} {
   cancelled;refresh_hw_vio $vio
   if {[llength $signal_probe]==1} {
    set sv [expr "0x[get_property INPUT_VALUE $signal_probe]"]
    set rejected_pulses [expr {($sv>>32)&0xffffffff}]
    if {$rejected_pulses!=$last_rejected_pulses} {
     set rp [get_hw_probes debug_camera -of_objects $vio]
     set_property INPUT_VALUE_RADIX HEX $rp
     set rv [expr "0x[get_property INPUT_VALUE $rp]"]
     set ef [open [file join $folder sync_events.jsonl] a]
     puts $ef "{\"capture\":[expr {$saved+1}],\"rows\":[expr {$rv&0xffffffff}],\"read_bytes\":[expr {($rv>>32)&0xffffffff}],\"rejected\":$rejected_pulses,\"max_low_cycles\":[expr {($sv>>64)&0xffffffff}]}"
     close $ef
     set last_rejected_pulses $rejected_pulses
    }
   }
   if {[value error] || [value rejected]} {
    set snapshot [open [file join $folder failure_snapshot.json] w]
    set cp [get_hw_probes debug_camera -of_objects $vio]
    set_property INPUT_VALUE_RADIX HEX $cp
    set cv [expr "0x[get_property INPUT_VALUE $cp]"]
    set cw {}
    for {set wi 0} {$wi<8} {incr wi} {lappend cw [expr {($cv>>(32*$wi))&0xffffffff}]}
    set sw {}
    if {[llength $signal_probe]==1} {
     for {set wi 0} {$wi<4} {incr wi} {lappend sw [expr {($sv>>(32*$wi))&0xffffffff}]}
    }
    puts $snapshot "{\"capture\":[expr {$saved+1}],\"combined_error\":[value error],\"metrics\":\[[join $cw ,]\],\"sync_metrics\":\[[join $sw ,]\]}"
    close $snapshot
    error "FPGA error code=[value error] rejected=[value rejected]"
   }
   if {[value finished] && ![value busy]} {break}
   if {[clock milliseconds]>$limit} {error "Capture timeout"}
   after 30
  }
  set mp [get_hw_probes -of_objects $vio -filter {NAME =~ *debug_camera*}]
  if {[llength $mp]!=1} {puts "PROBES [get_hw_probes -of_objects $vio]";error "Missing camera diagnostic vector"}
  set_property INPUT_VALUE_RADIX HEX $mp
  set metrics [expr "0x[get_property INPUT_VALUE $mp]"]
  set mf [open [file join $folder [format "metrics_%04d.json" [expr {$saved+1}]]] w]
  set words {}
  for {set wi 0} {$wi<8} {incr wi} {lappend words [expr {($metrics>>(32*$wi))&0xffffffff}]}
  puts $mf "\[[join $words ,]\]"
  close $mf

  set sp [get_hw_probes -quiet debug_sync -of_objects $vio]
  if {[llength $sp]==1} {
   set_property INPUT_VALUE_RADIX HEX $sp
   set syncv [expr "0x[get_property INPUT_VALUE $sp]"]
   set swds {}
   for {set wi 0} {$wi<4} {incr wi} {lappend swds [expr {($syncv>>(32*$wi))&0xffffffff}]}
   set sf [open [file join $folder [format "sync_%04d.json" [expr {$saved+1}]]] w]
   puts $sf "\[[join $swds ,]\]"
   close $sf
  }

  set ack [file join $folder [format "capture_%04d.ack" [expr {$saved+1}]]]
  set limit [expr {[clock milliseconds]+20000}]
  while {![file exists $ack]} {cancelled;if {[clock milliseconds]>$limit} {error "Save/display acknowledgement timeout"};after 20}
  puts "EDGE_SAVED [expr {$saved+1}]/$count";flush stdout
  after 600
 }
 puts "PASS EDGE_CAPTURE $count";flush stdout
} finally {
 catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
}




