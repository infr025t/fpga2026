$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$work=Join-Path $root 'reports/prefix_rtl';New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
 $v=(Get-FpgaVivadoBin)
 & "$v/xvlog.bat" -sv @(Get-RtlSources -Root $root) ../../sim/tb_prefix_filter.sv
 if($LASTEXITCODE){throw 'compile failed'}
 & "$v/xelab.bat" tb_prefix_filter -s prefix_tb
 if($LASTEXITCODE){throw 'elaborate failed'}
 & "$v/xsim.bat" prefix_tb -runall -log green.log
 if($LASTEXITCODE -or !(Select-String green.log -Pattern 'PASS ALL prefix RTL' -Quiet)){throw 'prefix test failed'}
}finally{Pop-Location}
