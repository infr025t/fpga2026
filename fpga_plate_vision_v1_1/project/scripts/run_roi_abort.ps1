$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$run=Join-Path $root 'build/sim_roi_abort';New-Item -ItemType Directory -Force "$run/model" | Out-Null
Copy-Item "$root/model/*.hex" "$run/model" -Force
$bin=(Get-FpgaVivadoBin)
Push-Location $run
try {
 & "$bin/xvlog.bat" -sv @(Get-RtlSources -Root $root) "$root/sim/tb_roi_abort.sv"
 if($LASTEXITCODE){throw 'compile modes'}
 & "$bin/xelab.bat" tb_roi_abort -s modes
 if($LASTEXITCODE){throw 'elaborate modes'}
 & "$bin/xsim.bat" modes -runall -log modes.log
 if($LASTEXITCODE -or !(Select-String modes.log -Pattern 'PASS ROI abort and mode transitions' -Quiet)){throw 'mode test failed'}
}finally{Pop-Location}
