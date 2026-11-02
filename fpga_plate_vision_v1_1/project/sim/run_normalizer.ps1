param([string]$Vivado='')
$ErrorActionPreference="Stop"
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$Vivado=Get-FpgaVivadoBin -Override $Vivado
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$work=Join-Path $root "reports/norm_rtl"
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
 & "$Vivado/xvlog.bat" -sv @(Get-RtlSources -Root $root) ../../sim/tb_char_normalizer.sv ../../sim/tb_u32_div.sv
 if($LASTEXITCODE){throw "xvlog failed"}
 & "$Vivado/xelab.bat" tb_char_normalizer -s norm_tb --timescale 1ns/1ps
 if($LASTEXITCODE){throw "xelab failed"}
 "run all`nquit" | Set-Content run.tcl
 & "$Vivado/xsim.bat" norm_tb -tclbatch run.tcl -log green.log
 if($LASTEXITCODE){throw "xsim failed"}
 if(!(Select-String -Path green.log -Pattern "PASS ALL normalizer" -Quiet)){throw "Simulation did not pass"}
 & "$Vivado/xelab.bat" tb_u32_div -s div_tb --timescale 1ns/1ps
 if($LASTEXITCODE){throw "Divider elaboration failed"}
 & "$Vivado/xsim.bat" div_tb -tclbatch run.tcl -log divider.log
 if($LASTEXITCODE){throw "Divider simulation failed"}
 if(!(Select-String -Path divider.log -Pattern "PASS ALL divider" -Quiet)){throw "Divider did not pass"}
} finally {Pop-Location}
