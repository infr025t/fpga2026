# 共享 VIO 操作；这里只定义函数和解析选项，不打开或下载硬件。
set root [file normalize [file join [file dirname [info script]] ..]]
set snapshot_mode 1
set artifact_dir [file join $root artifacts]
set positional {}
for {set i 0} {$i<[llength $argv]} {incr i} {
 set arg [lindex $argv $i]
 switch -- $arg {
  -snapshot {set snapshot_mode 1}
  -no-snapshot {set snapshot_mode 0}
  -artifact-dir {
   incr i
   if {$i>=[llength $argv]} {error "-artifact-dir requires a path"}
   set artifact_dir [file normalize [lindex $argv $i]]
  }
  default {lappend positional $arg}
 }
}
set argv $positional
set probe_name [expr {$snapshot_mode?{lcd_top_snapshot}:{lcd_top}}]
proc require_artifact {name} {
 global artifact_dir
 set path [file join $artifact_dir $name]
 if {![file isfile $path]} {error "Missing artifact: $path"}
 return $path
}
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
