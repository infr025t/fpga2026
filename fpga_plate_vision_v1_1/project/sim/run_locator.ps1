$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
& (Get-FpgaPython) "$root/scripts/make_locator_vectors.py"
if($LASTEXITCODE){throw 'vectors failed'}
$work=Join-Path $root 'reports/locator_rtl';New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
 $v=(Get-FpgaVivadoBin)
 & "$v/xvlog.bat" -sv @(Get-RtlSources -Root $root) ../../sim/tb_plate_region_locator.sv
 if($LASTEXITCODE){throw 'compile failed'}
 & "$v/xelab.bat" tb_plate_region_locator -s locator_tb
 if($LASTEXITCODE){throw 'elaborate failed'}
 & "$v/xsim.bat" locator_tb -runall -log green.log
 if($LASTEXITCODE -or !(Select-String green.log -Pattern 'PASS ALL locator RTL' -Quiet)){throw 'locator test failed'}
}finally{Pop-Location}
