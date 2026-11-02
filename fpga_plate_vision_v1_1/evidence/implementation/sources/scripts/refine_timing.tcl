# 复用已布线设计做物理优化；不修改RTL、时钟或IO时序约束。
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build_verified]
if {[llength $argv]} {set out [file normalize [lindex $argv 0]]}
open_checkpoint [file join $out post_route.dcp]
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
write_checkpoint -force [file join $out post_route_refined.dcp]
report_timing_summary -report_unconstrained -file [file join $out timing_refined.rpt]
report_utilization -hierarchical -file [file join $out utilization_refined.rpt]
report_drc -file [file join $out drc_refined.rpt]
report_bus_skew -file [file join $out bus_skew_refined.rpt]
check_timing -verbose -file [file join $out check_timing_refined.rpt]
foreach delay {max min} {
 set paths [get_timing_paths -delay_type $delay -max_paths 1]
 if {![llength $paths] || [get_property SLACK $paths]<0} {error "Timing $delay still failed after physical refinement"}
}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "Severe DRC"}
write_bitstream -force [file join $out autonomous_board.bit]
write_debug_probes -force [file join $out autonomous_board.ltx]
puts "PASS AUTONOMOUS_BOARD_REFINED_BUILD"
