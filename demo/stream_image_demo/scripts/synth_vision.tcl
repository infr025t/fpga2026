# OOC synthesis/resource check only. This does not generate a board bitstream.
# Run in a fresh Vivado Tcl session. Optional limits may be set before source.
set root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists vision_bram_limit]} {set vision_bram_limit 45}
if {![info exists vision_dsp_limit]} {set vision_dsp_limit 72}
if {![info exists vision_lut_limit]} {set vision_lut_limit 18000}
if {$vision_bram_limit <= 0 || $vision_bram_limit > 50 ||
    $vision_dsp_limit <= 0 || $vision_dsp_limit > 90 ||
    $vision_lut_limit <= 0 || $vision_lut_limit > 20800} {
    error "Invalid vision resource budget for XC7A35T."
}
if {[info exists ::env(VISION_BUILD_DIR)]} {
    set out [file normalize $::env(VISION_BUILD_DIR)]
} else {
    set out [file join $root build vision_ooc]
}
file mkdir $out
create_project -in_memory -part xc7a35tcpg236-1
read_verilog -sv [glob [file join $root rtl *.sv]]
read_xdc [file join $root constraints vision_ooc.xdc]
synth_design -top vision_top -mode out_of_context -part xc7a35tcpg236-1
report_utilization -file [file join $out utilization_synth.rpt]
report_timing_summary -file [file join $out timing_synth_estimate.rpt]
set bram36 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB36*}]]
set bram18 [llength [get_cells -hierarchical -filter {REF_NAME =~ RAMB18*}]]
set dsp [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]
set lut [llength [get_cells -hierarchical -filter {REF_NAME =~ LUT*}]]
set bram_equivalent [expr {$bram36 + $bram18 / 2.0}]
if {$bram_equivalent > $vision_bram_limit || $dsp > $vision_dsp_limit || $lut > $vision_lut_limit} {
    error "Vision core exceeds budget: BRAM36eq=$bram_equivalent DSP=$dsp LUT=$lut. Inspect utilization_synth.rpt."
}
write_checkpoint -force [file join $out vision_top_synth.dcp]
puts "PASS vision synthesis budget: BRAM36eq=$bram_equivalent DSP=$dsp LUT=$lut"
puts "OOC synthesis only; final display adapter, board I/O constraints, routing and timing are still required."
