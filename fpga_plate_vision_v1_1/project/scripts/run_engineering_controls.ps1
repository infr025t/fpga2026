$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$run=Join-Path $root 'build/sim_controls';New-Item -ItemType Directory -Force $run | Out-Null
$bin=(Get-FpgaVivadoBin)
Push-Location $run
try {
 & "$bin/xvlog.bat" -sv @(Get-RtlSources -Root $root) "$root/sim/tb_engineering_controls.sv"
 if($LASTEXITCODE){throw 'compile controls'}
 & "$bin/xelab.bat" tb_engineering_controls -s controls
 if($LASTEXITCODE){throw 'elaborate controls'}
 & "$bin/xsim.bat" controls -runall -log controls.log
 if($LASTEXITCODE -or !(Select-String controls.log -Pattern 'PASS engineering controls' -Quiet)){throw 'controls failed'}
}finally{Pop-Location}
