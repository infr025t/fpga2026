# Run from Vivado Tcl console: source E:/UESTC/FPGA/stream_image_demo/scripts/create_project.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
create_project stream_image_demo [file join $root vivado_project] -part xc7a35tcpg236-1 -force
add_files [glob [file join $root rtl *.sv]]
add_files -fileset constrs_1 [file join $root constraints basys3.xdc]
add_files -fileset sim_1 [glob [file join $root sim *.sv]]
set_property top stream_top [current_fileset]
set_property top tb_top [get_filesets sim_1]
update_compile_order -fileset sources_1
puts "Project ready. Run synthesis, implementation, then Generate Bitstream."
