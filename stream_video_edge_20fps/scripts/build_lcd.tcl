set root [file normalize [file join [file dirname [info script]] ..]]
set out [lindex $argv 0]
if {$out eq {}} {set out {E:/FPGA_Test_Work/lcd_v04_build}}
set snapshot [expr {[lindex $argv 1] eq {1}}]
set name [expr {$snapshot?{lcd_top_snapshot}:{lcd_top}}]
file mkdir $out
create_project -force lcd_v04 [file join $out project] -part xc7a35tcpg236-1
set defines {DIAG_JTAG}
if {$snapshot} {lappend defines LCD_SNAPSHOT}
set_property verilog_define $defines [current_fileset]
file mkdir [file join $out ip]
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name lcd_vio -dir [file join $out ip]
set config [list CONFIG.C_NUM_PROBE_IN [expr {$snapshot?8:4}] CONFIG.C_NUM_PROBE_OUT [expr {$snapshot?3:2}] CONFIG.C_PROBE_IN0_WIDTH 32 CONFIG.C_PROBE_IN1_WIDTH 256 CONFIG.C_PROBE_IN2_WIDTH 128 CONFIG.C_PROBE_OUT0_WIDTH 16 CONFIG.C_PROBE_OUT1_WIDTH 2 CONFIG.C_PROBE_OUT0_INIT_VAL 0x0000 CONFIG.C_PROBE_OUT1_INIT_VAL 0x0 CONFIG.C_EN_PROBE_IN_ACTIVITY 0]
if {$snapshot} {
 for {set i 3} {$i<=5} {incr i} {lappend config CONFIG.C_PROBE_IN[set i]_WIDTH 256}
 lappend config CONFIG.C_PROBE_IN7_WIDTH 128 CONFIG.C_PROBE_IN6_WIDTH 32 CONFIG.C_PROBE_OUT2_WIDTH 11 CONFIG.C_PROBE_OUT2_INIT_VAL 0x0
} else {lappend config CONFIG.C_PROBE_IN3_WIDTH 256}
set_property -dict $config [get_ips lcd_vio]
generate_target all [get_ips lcd_vio]
synth_ip [get_ips lcd_vio]
read_verilog -sv [glob [file join $root rtl core *.sv]]
foreach d {camera display runtime} {read_verilog -sv [glob [file join $root rtl $d *.sv]]}
if {$snapshot} {read_verilog -sv [glob [file join $root rtl debug *.sv]]}
read_verilog -sv [file join $root rtl uart uart_fast_tx.sv]
read_verilog -sv [file join $root rtl lcd_top.sv]
read_xdc [file join $root constraints basys3_camera_lcd.xdc]
set stat_frames [lindex $argv 2]
if {$stat_frames eq {}} {set stat_frames 0}
synth_design -top lcd_top -part xc7a35tcpg236-1 -generic STAT_FRAMES=$stat_frames
if {[llength [get_cells -hier -filter {REF_NAME =~ LD*}]]} {error "Unexpected latch"}
# Apply on actual synthesized IBUF cells; port-only assignment did not disable ZHOLD.
set camera_ibufs [get_cells -hier -filter {REF_NAME == IBUF && NAME =~ cam_data_IBUF*}]
if {[llength $camera_ibufs]!=8} {error "Expected8 camera input buffers"}
set_property IOBDELAY NONE $camera_ibufs
foreach c $camera_ibufs {puts "CAMERA_IBUF $c IOBDELAY=[get_property IOBDELAY $c]"}
write_checkpoint -force [file join $out post_synth.dcp]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $out post_route.dcp]
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -report_unconstrained -file [file join $out timing.rpt]
report_drc -file [file join $out drc.rpt]
report_bus_skew -file [file join $out bus_skew.rpt]
check_timing -verbose -file [file join $out check_timing.rpt]
foreach delay {max min} {
 set paths [get_timing_paths -delay_type $delay -max_paths 1]
 if {![llength $paths] || [get_property SLACK $paths]<0} {error "Timing $delay failed"}
}
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error || SEVERITY == {Critical Warning}}]]} {error "Severe DRC"}
write_bitstream -force [file join $out $name.bit]
write_debug_probes -force [file join $out $name.ltx]
foreach ext {bit ltx} {file copy -force [file join $out $name.$ext] [file join $root artifacts $name.$ext]}
puts "PASS LCD_V04_BUILD $name"
