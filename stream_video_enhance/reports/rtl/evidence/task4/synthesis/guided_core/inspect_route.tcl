open_checkpoint E:/Vivado_FPGA_Programs/fpga2026/stream_video_enhance/build/regression/synthesis/20261026-191854/guided_core/routed.dcp
set out E:/Vivado_FPGA_Programs/fpga2026/stream_video_enhance/build/regression/synthesis/20261026-191854/guided_core
report_timing -delay_type min_max -from [all_registers -clock core_clk] -to [all_registers -clock core_clk] -max_paths 5 -file $out/routed_registered_paths.rpt
set f [open $out/routed_internal_metrics.json w]
puts $f \{
puts $f "\"registered_setup_slack_ns\": [get_property SLACK [get_timing_paths -from [all_registers -clock core_clk] -to [all_registers -clock core_clk] -max_paths 1]],"
puts $f "\"registered_hold_slack_ns\": [get_property SLACK [get_timing_paths -delay_type min -from [all_registers -clock core_clk] -to [all_registers -clock core_clk] -max_paths 1]]"
puts $f \}
close $f
