set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build release_01]
if {[llength $argv]} {set out [file normalize [lindex $argv 0]]}
open_checkpoint [file join $out post_route.dcp]
report_timing -max_paths 100 -slack_lesser_than 0 -file [file join $out failing_paths.rpt]
