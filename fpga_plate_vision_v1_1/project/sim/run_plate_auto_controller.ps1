param([string]$Vivado='',[string]$Log="green.log")
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$Vivado=Get-FpgaVivadoBin -Override $Vivado
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$work=Join-Path $root "reports/auto_controller_rtl"
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
 & "$Vivado/xvlog.bat" -sv @(Get-RtlSources -Root $root) ../../sim/tb_plate_auto_controller.sv
 if($LASTEXITCODE){throw "xvlog failed"}
 & "$Vivado/xelab.bat" tb_plate_auto_controller -s auto_controller_tb --timescale 1ns/1ps
 if($LASTEXITCODE){throw "xelab failed"}
 "run all`nquit" | Set-Content run.tcl
 & "$Vivado/xsim.bat" auto_controller_tb -tclbatch run.tcl -log $Log
 if($LASTEXITCODE){throw "xsim failed"}
 if(!(Select-String -Path $Log -Pattern "PASS ALL plate_auto_controller" -Quiet)){throw "Controller simulation did not pass"}
} finally {Pop-Location}
