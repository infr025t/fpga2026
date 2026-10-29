# Release JTAG switch override without reprogramming or changing pixels.
open_hw_manager
connect_hw_server -url localhost:3121
set target [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
if {[llength $target]!=1} {error "Expected task Basys3"}
current_hw_target [lindex $target 0]
open_hw_target
try {
 set root [file normalize [file join [file dirname [info script]] ..]]
 set dev [get_hw_devices xc7a35t_0]
 set_property PROBES.FILE [file join $root artifacts edge_top.ltx] $dev
 refresh_hw_device $dev
 set vio [get_hw_vios -of_objects $dev]
 set control [get_hw_probes debug_control -of_objects $vio]
 if {[llength $control]!=1} {error "Expected override control"}
 set_property OUTPUT_VALUE_RADIX HEX $control
 set_property OUTPUT_VALUE 0 $control
 commit_hw_vio $control
 puts "PASS PHYSICAL_SWITCHES_ENABLED"
} finally {
 catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}
}
