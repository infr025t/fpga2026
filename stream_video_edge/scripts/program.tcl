set root [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
if {[llength $targets]!=1} {error "Expected this task's Basys3 serial210183BCBF83A"}
current_hw_target [lindex $targets 0]
open_hw_target
try {
 set dev [get_hw_devices xc7a35t_0]
 if {[llength $dev]!=1} {error "Expected one Artix7"}
 current_hw_device $dev
 set_property PROGRAM.FILE [file join $root artifacts edge_top.bit] $dev
 set_property PROBES.FILE [file join $root artifacts edge_top.ltx] $dev
 program_hw_devices $dev
 refresh_hw_device $dev
 # Manual operation must use physical switches after programming. The
 # automatic controller explicitly claims VIO override when it starts.
 set vio [get_hw_vios -of_objects $dev]
 set control [get_hw_probes debug_control -of_objects $vio]
 if {[llength $control]!=1} {error "Missing debug switch control"}
 set_property OUTPUT_VALUE_RADIX HEX $control
 set_property OUTPUT_VALUE 0 $control
 commit_hw_vio $control
 puts "PASS EDGE_PROGRAM"
} finally {
 catch {close_hw_target}
 catch {disconnect_hw_server}
 catch {close_hw_manager}
}
