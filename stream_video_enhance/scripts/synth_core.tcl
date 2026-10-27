# Local OOC only: identical target, clock and boundary budget for every top.
set root [file normalize [lindex $argv 0]]
set top [lindex $argv 1]
set out [file normalize [lindex $argv 2]]
file mkdir $out
create_project -in_memory -part xc7a35tcpg236-1
set packages {core_latency_pkg.sv video_runtime_pkg.sv}
foreach package $packages {read_verilog -sv [file join $root rtl $package]}
foreach src [glob [file join $root rtl *.sv]] {
    if {[file tail $src] ni $packages} {read_verilog -sv $src}
}
foreach src [glob -nocomplain [file join $root rtl experiments *.sv]] {read_verilog -sv $src}
set constraints [open [file join $out input_constraints.xdc] w]
puts $constraints {create_clock -name core_clk -period 10.000 [get_ports clk]}
# A local OOC clock anchor, not an assignment for the future board top.
puts $constraints {set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]}
puts $constraints {set_input_delay -clock core_clk -max 2.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]}
puts $constraints {set_input_delay -clock core_clk -min 0.000 [get_ports -filter {DIRECTION == IN && NAME != clk}]}
puts $constraints {set_output_delay -clock core_clk -max 2.000 [get_ports -filter {DIRECTION == OUT}]}
puts $constraints {set_output_delay -clock core_clk -min 0.000 [get_ports -filter {DIRECTION == OUT}]}
close $constraints
read_xdc [file join $out input_constraints.xdc]
synth_design -top $top -mode out_of_context -part xc7a35tcpg236-1 -generic W=640 -generic H=480
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -from [all_registers -clock core_clk] -to [all_registers -clock core_clk] -max_paths 10 -file [file join $out registered_paths.rpt]
report_drc -checks {MDRV-1 LUTLP-1} -file [file join $out drc.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
write_checkpoint -force [file join $out synthesized.dcp]
write_xdc -force [file join $out constraints.xdc]
set f [open [file join $out metrics.json] w]
puts $f "\{"
puts $f "  \"tool\": \"[version -short]\","
foreach {key filter} {RAMB18 {REF_NAME =~ RAMB18*} RAMB36 {REF_NAME =~ RAMB36*} DSP {REF_NAME =~ DSP48*} LUT_PRIMITIVES {REF_NAME =~ LUT*} FF {REF_NAME =~ FD*} latches {REF_NAME =~ LD*}} {
  puts $f "  \"$key\": [llength [get_cells -quiet -hier -filter $filter]],"
}
puts $f "  \"multidrivers\": [llength [get_drc_violations -quiet -filter {NAME =~ MDRV-1*}]],"
puts $f "  \"combinational_loops\": [llength [get_drc_violations -quiet -filter {NAME =~ LUTLP-1*}]],"
set regpath [get_timing_paths -from [all_registers -clock core_clk] -to [all_registers -clock core_clk] -max_paths 1]
set anypath [get_timing_paths -max_paths 1]
set reghold [get_timing_paths -delay_type min -from [all_registers -clock core_clk] -to [all_registers -clock core_clk] -max_paths 1]
set anyhold [get_timing_paths -delay_type min -max_paths 1]
puts $f "  \"registered_setup_slack_ns\": [get_property SLACK $regpath],"
puts $f "  \"registered_hold_slack_ns\": [get_property SLACK $reghold],"
puts $f "  \"overall_hold_slack_ns\": [get_property SLACK $anyhold],"
puts $f "  \"overall_setup_slack_ns\": [get_property SLACK $anypath]"
puts $f "\}"
close $f
if {[lindex $argv 3] eq "route"} {
  # Optional bounded implementation of the numerical OOC core only.
  # No board top, I/O pads, camera, bitstream or download are involved.
  opt_design
  place_design
  phys_opt_design
  route_design
  report_utilization -file [file join $out routed_utilization.rpt]
  report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out routed_timing_summary.rpt]
  report_route_status -file [file join $out route_status.rpt]
  check_timing -verbose -file [file join $out routed_check_timing.rpt]
  write_checkpoint -force [file join $out routed.dcp]
  set f [open [file join $out routed_metrics.json] w]
  puts $f "\{"
  puts $f "  \"setup_slack_ns\": [get_property SLACK [get_timing_paths -max_paths 1]],"
  puts $f "  \"hold_slack_ns\": [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
  puts $f "\}"
  close $f
}
puts "PASS SYNTH"
