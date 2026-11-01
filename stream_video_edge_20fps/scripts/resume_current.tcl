source [file join [file dirname [info script]] hardware_common.tcl]
set report_root [file join $root reports lcd runtime]
file mkdir $report_root
set label [lindex $argv 0]
set mode [lindex $argv 1]
set max_records [lindex $argv 2]
if {$max_records eq {}} {set max_records 0}
if {![string is integer -strict $max_records] || $max_records<0} {error "Invalid optional record limit"}
if {$mode ni {0 1 2 4 5 6}} {error "mode0 scene RAW,1 internal RAW,2 sensor bars RAW,4 scene EDGE,5 internal EDGE,6 sensor bars EDGE"}
set expected_pixels [expr {($mode&4)?296100:307200}]
if {![regexp {^[A-Za-z0-9_-]+$} $label]} {error "Specify a unique label"}
set folder [file join $report_root $label]
if {[file exists $folder]} {error "Preserve previous run"}
file mkdir $folder
open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -filter {NAME =~ *210183BCBF83A}]
if {[llength $targets]!=1} {error "Expected task Basys3"}
current_hw_target [lindex $targets 0];open_hw_target
set dev [get_hw_devices xc7a35t_0]
set_property PROBES.FILE [require_artifact $probe_name.ltx] $dev
refresh_hw_device $dev
set vio [get_hw_vios -of_objects $dev]
if {[llength $vio]!=1} {error "Expected one LCD VIO"}



try {
 drive 0 [expr {0x8000|$mode}];drive 1 1;wait_ready
 drive 0 $mode;after 20
 puts "CURRENT_RUN mode=$mode status=[status]"
} finally {catch {close_hw_target};catch {disconnect_hw_server};catch {close_hw_manager}}
