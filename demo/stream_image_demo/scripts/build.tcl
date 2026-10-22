set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build vivado]
file mkdir $out
create_project -in_memory -part xc7a35tcpg236-1
read_verilog -sv [glob [file join $root rtl *.sv]]
read_xdc [file join $root constraints basys3.xdc]
synth_design -top stream_top -part xc7a35tcpg236-1
report_utilization -file [file join $out utilization_synth.rpt]
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file [file join $out timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
write_checkpoint -force [file join $out stream_top_routed.dcp]
set worst [get_timing_paths -delay_type max -max_paths 1]
if {[get_property SLACK $worst] < 0} {error "Setup timing failed; inspect timing.rpt before using hardware."}
set worst_hold [get_timing_paths -delay_type min -max_paths 1]
if {[get_property SLACK $worst_hold] < 0} {error "Hold timing failed; inspect timing.rpt."}
write_bitstream -force [file join $out stream_top.bit]
