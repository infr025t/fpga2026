$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
$run=Join-Path $root 'build/sim_roi_overlay';New-Item -ItemType Directory -Force $run | Out-Null
$bin=(Get-FpgaVivadoBin)
Push-Location $run
try {
 & "$bin/xvlog.bat" -sv "$root/rtl/video/plate_roi_overlay.sv" "$root/sim/tb_roi_overlay.sv"
 if($LASTEXITCODE){throw 'compile ROI'}
 & "$bin/xelab.bat" tb_roi_overlay -s roi
 if($LASTEXITCODE){throw 'elaborate ROI'}
 & "$bin/xsim.bat" roi -runall -log roi.log
 if($LASTEXITCODE -or !(Select-String roi.log -Pattern 'PASS ROI bounds' -Quiet)){throw 'ROI checks failed'}
}finally{Pop-Location}
