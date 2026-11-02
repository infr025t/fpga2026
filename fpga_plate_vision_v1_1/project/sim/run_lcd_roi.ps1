param([string]$Vivado='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$Vivado=Get-FpgaVivadoBin -Override $Vivado
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$work=Join-Path $root 'build/sim_lcd_roi'
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
 & "$Vivado/xvlog.bat" -sv @(Get-RtlSources -Root $root) ../../sim/tb_lcd_roi.sv
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$Vivado/xelab.bat" tb_lcd_roi -s lcd_roi_tb --timescale 1ns/1ps
 if($LASTEXITCODE){throw 'xelab failed'}
 "run all`nquit" | Set-Content run.tcl
 & "$Vivado/xsim.bat" lcd_roi_tb -tclbatch run.tcl -log green.log
 if($LASTEXITCODE -or !(Select-String -Path green.log -Pattern 'PASS ALL LCD ROI' -Quiet)){throw 'LCD pin simulation failed'}
} finally {Pop-Location}
