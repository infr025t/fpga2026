set root [file normalize [file join [file dirname [info script]] ..]]
set out {E:/FPGA_Test_Work/edge_v03_work/stable_board}
file mkdir $out
create_project -force edge_debug [file join $out project] -part xc7a35tcpg236-1
set_property verilog_define {DIAG_JTAG} [current_fileset]
file mkdir [file join $out ip]
if {[file exists [file join $out ip diag_vio diag_vio.xci]]} {
 read_ip [file join $out ip diag_vio diag_vio.xci]
} else {
 create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name diag_vio -dir [file join $out ip]
}
set_property -dict [list CONFIG.C_NUM_PROBE_IN 3 CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 256 CONFIG.C_PROBE_IN2_WIDTH 128 CONFIG.C_NUM_PROBE_OUT 2 CONFIG.C_PROBE_OUT0_WIDTH 16 CONFIG.C_PROBE_OUT1_WIDTH 2 CONFIG.C_PROBE_OUT0_INIT_VAL 0x0000 CONFIG.C_PROBE_OUT1_INIT_VAL 0x1 CONFIG.C_EN_PROBE_IN_ACTIVITY 0] [get_ips diag_vio]
generate_target all [get_ips diag_vio]
synth_ip [get_ips diag_vio]
read_verilog -sv [file join $root rtl core core_latency_pkg.sv]
foreach source [glob [file join $root rtl core *.sv]] {
 if {[file tail $source] ne "core_latency_pkg.sv"} {read_verilog -sv $source}
}
foreach folder {camera uart display} {read_verilog -sv [glob [file join $root rtl $folder *.sv]]}
read_verilog -sv [file join $root rtl edge_top.sv]
read_xdc [file join $root constraints basys3_camera_uart.xdc]


synth_design -top edge_top -part xc7a35tcpg236-1
set latches [get_cells -hier -filter {REF_NAME =~ LD*}]
if {[llength $latches]} {error "unexpected latch"}
report_utilization -file [file join $out synth_utilization.rpt]
opt_design
place_design
phys_opt_design
route_design
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $out timing.rpt]
report_drc -file [file join $out drc.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
write_checkpoint -force [file join $out edge_top_routed.dcp]
foreach delay {max min} {
 set paths [get_timing_paths -delay_type $delay -max_paths 1]
 if {![llength $paths] || [get_property SLACK $paths]<0} {error "Timing $delay failed"}
}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "severe DRC"}
write_bitstream -force [file join $out edge_top.bit]
write_debug_probes -force [file join $out edge_top.ltx]

foreach name {edge_top.bit edge_top.ltx} {file copy -force [file join $out $name] [file join $root artifacts $name]}
puts "PASS EDGE_BUILD [file join $root artifacts edge_top.bit]"







