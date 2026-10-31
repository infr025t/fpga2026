set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build video_x6_barcheck_slow]
file mkdir $out
open_checkpoint [file join $root build video_x6_barcheck post_route.dcp]
set_property SLEW SLOW [get_ports cam_rclk]
# Change only physical output slew; preserve clock period, enables, placement and data path.
report_timing_summary -report_unconstrained -file [file join $out timing.rpt]
report_drc -file [file join $out drc.rpt]
foreach delay {max min} {
 set p [get_timing_paths -delay_type $delay -max_paths 1]
 if {![llength $p] || [get_property SLACK $p]<0} {error "Timing failed"}
}
write_checkpoint -force [file join $out post_route.dcp]
write_bitstream -force [file join $out lcd_top_snapshot.bit]
write_debug_probes -force [file join $out lcd_top_snapshot.ltx]
foreach ext {bit ltx} {file copy -force [file join $out lcd_top_snapshot.$ext] [file join $root artifacts lcd_top_snapshot.$ext]}
puts "PASS SLOW_RCLK_ONLY"
