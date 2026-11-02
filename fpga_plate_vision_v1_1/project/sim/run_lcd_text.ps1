param([string]$Vivado='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$Vivado=Get-FpgaVivadoBin -Override $Vivado
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$work=Join-Path $root 'reports/lcd_text_rtl'
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
 & "$Vivado/xvlog.bat" -sv @(Get-RtlSources -Root $root) ../../sim/tb_lcd_text.sv
 if($LASTEXITCODE){throw 'xvlog failed'}
 & "$Vivado/xelab.bat" tb_lcd_text -s lcd_text_tb --timescale 1ns/1ps
 if($LASTEXITCODE){throw 'xelab failed'}
 "run all`nquit" | Set-Content run.tcl
 & "$Vivado/xsim.bat" lcd_text_tb -tclbatch run.tcl -log green.log
 if($LASTEXITCODE -or !(Select-String -Path green.log -Pattern 'PASS ALL LCD text' -Quiet)){throw 'LCD pin simulation failed'}
} finally {Pop-Location}
