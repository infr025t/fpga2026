# Resolve Python through the same configuration as the PowerShell entry points.
set fpga_toolchain_dir [file dirname [info script]]
proc fpga_python {} {
    global fpga_toolchain_dir tcl_platform
    if {$tcl_platform(platform) eq "windows"} {
        set shell [auto_execok powershell.exe]
        if {$shell eq ""} {error "PowerShell is required to resolve FPGA_PYTHON"}
        return [string trim [exec {*}$shell -NoProfile -ExecutionPolicy Bypass -File [file join $fpga_toolchain_dir toolchain.ps1] -Tool python]]
    }
    if {[info exists ::env(FPGA_PYTHON)] && $::env(FPGA_PYTHON) ne ""} {
        if {![file executable $::env(FPGA_PYTHON)]} {error "Invalid FPGA_PYTHON executable"}
        return $::env(FPGA_PYTHON)
    }
    foreach name {python3 python} {
        set command [auto_execok $name]
        if {$command ne ""} {return [lindex $command 0]}
    }
    error "Python was not found; set FPGA_PYTHON"
}
