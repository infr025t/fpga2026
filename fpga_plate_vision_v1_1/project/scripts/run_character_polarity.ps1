$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$run=Join-Path $root 'build/sim_character_polarity';New-Item -ItemType Directory -Force "$run/model" | Out-Null
Copy-Item "$root/model/*.hex" "$run/model" -Force
$bin=(Get-FpgaVivadoBin)
Push-Location $run
try {
 & "$bin/xvlog.bat" -sv @(Get-RtlSources -Root $root) "$root/sim/tb_character_polarity.sv"
 if($LASTEXITCODE){throw 'compile modes'}
 & "$bin/xelab.bat" tb_character_polarity -s modes
 if($LASTEXITCODE){throw 'elaborate modes'}
 & "$bin/xsim.bat" modes -runall -log modes.log
 if($LASTEXITCODE -or !(Select-String modes.log -Pattern 'PASS character polarity' -Quiet)){throw 'mode test failed'}
}finally{Pop-Location}
