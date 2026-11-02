# 仅操作Basys3配置RAM和VIO；Flash不参与本次测试。
set root [file normalize [file join [file dirname [info script]] ..]]
set build [file normalize [file join $root .. release]]
if {[llength $argv]>1} {set build [file normalize [lindex $argv 1]]}
set action [lindex $argv 0]
if {$action ni {probe program camera cnn auto auto_white pair internal edge raw physical status}} {error "Expected probe/program/auto/auto_white/pair/cnn/internal/edge/raw/physical/status"}
if {$action ne "probe" && ![file isfile [file join $build autonomous_board.ltx]]} {error "Missing probe file in $build; supply an explicit build directory"}
if {$action eq "program" && ![file isfile [file join $build autonomous_board.bit]]} {error "Missing bitstream in $build; supply an explicit build directory"}
open_hw_manager
connect_hw_server -url localhost:3121
try {
 set targets [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
 if {[llength $targets]!=1} {error "Expected Basys3 210183BCBF83A"}
 current_hw_target [lindex $targets 0]
 set_property PARAM.FREQUENCY 3000000 [current_hw_target]
 open_hw_target
 set dev [get_hw_devices xc7a35t_0]
 if {[llength $dev]!=1} {error "Expected XC7A35T"}
 current_hw_device $dev
 if {$action eq {probe}} {puts "PASS BOARD_PRESENT"} else {
  set_property PROBES.FILE [file join $build autonomous_board.ltx] $dev
  if {$action eq {program}} {
   set_property PROGRAM.FILE [file join $build autonomous_board.bit] $dev
   program_hw_devices $dev
  }
  refresh_hw_device $dev
  set vio [get_hw_vios -of_objects $dev]
  if {[llength $vio]!=1} {error "Expected one VIO"}
  proc drive {port value} {
   global vio
   set p [get_hw_probes -of_objects $vio -filter "TYPE == vio_output && PROBE_PORT == $port"]
   if {[llength $p]!=1} {error "Expected complete output probe"}
   set_property OUTPUT_VALUE_RADIX HEX $p
   set_property OUTPUT_VALUE [format %0*x [expr {([get_property WIDTH $p]+3)/4}] $value] $p
   commit_hw_vio $p
  }
  if {$action in {cnn camera auto auto_white pair internal edge raw}} {
   set controls [dict create cnn 0x2000 camera 0x1000 pair 0x1000 auto 0x0010 auto_white 0x0030 internal 1 edge 8 raw 0]
   drive 0 [dict get $controls $action];drive 1 1;after 100
  }
  if {$action eq {physical}} {drive 1 0}
  set input_probes [get_hw_probes -of_objects $vio -filter {TYPE == vio_input}]
  set_property INPUT_VALUE_RADIX HEX $input_probes
  refresh_hw_vio $vio
  after 50
  refresh_hw_vio $vio
  foreach p [get_hw_probes -of_objects $vio -filter {TYPE == vio_input}] {
   puts "PROBE [get_property PROBE_PORT $p] [get_property PROBE_PORT_BITS $p] [get_property INPUT_VALUE $p]"
  }
  puts "PASS HW_ACTION $action"
 }
} finally {catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}}
