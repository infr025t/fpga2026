param([string]$Vivado='')
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$Vivado=Get-FpgaVivadoBin -Override $Vivado
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$work=Join-Path $root "reports/auto_uart_rtl"
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
 & "$Vivado/xvlog.bat" -sv @(Get-RtlSources -Root $root) ../../sim/tb_plate_auto_uart.sv
 if($LASTEXITCODE){throw "xvlog failed"}
 & "$Vivado/xelab.bat" tb_plate_auto_uart -s auto_uart_tb --timescale 1ns/1ps
 if($LASTEXITCODE){throw "xelab failed"}
 "run all`nquit" | Set-Content run.tcl
 & "$Vivado/xsim.bat" auto_uart_tb -tclbatch run.tcl -log green.log
 if($LASTEXITCODE){throw "xsim failed"}
 if(!(Select-String -Path green.log -Pattern "PASS ALL auto UART" -Quiet)){throw "Simulation did not pass"}
 & (Get-FpgaPython) ../../sim/check_auto_uart.py uart_bytes.hex
 if($LASTEXITCODE){throw "Python UART oracle failed"}
 & (Get-FpgaPython) ../../pc/test_auto_protocol.py
 if($LASTEXITCODE){throw "Python parser tests failed"}
} finally {Pop-Location}
