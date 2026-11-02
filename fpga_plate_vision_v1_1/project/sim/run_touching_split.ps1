$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
& (Get-FpgaPython) "$root/scripts/make_split_vectors.py"
if($LASTEXITCODE){throw 'vector generation'}
$work=Join-Path $root 'reports/split_rtl';New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item "$root/sim/split_vectors/*" -Destination $work -Force
Push-Location $work
try {
 $v=(Get-FpgaVivadoBin)
 & "$v/xvlog.bat" -sv @(Get-RtlSources -Root $root) ../../sim/tb_touching_split.sv
 if($LASTEXITCODE){throw 'compile failed'}
 & "$v/xelab.bat" tb_touching_split -s split_tb
 if($LASTEXITCODE){throw 'elaborate failed'}
 & "$v/xsim.bat" split_tb -runall -log green.log
 if($LASTEXITCODE -or !(Select-String green.log -Pattern 'PASS ALL touching split RTL' -Quiet)){throw 'split test failed'}
}finally{Pop-Location}
