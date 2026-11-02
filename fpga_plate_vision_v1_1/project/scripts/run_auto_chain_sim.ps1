param([string]$Tag='auto_chain')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
& (Get-FpgaPython) "$root/scripts/make_auto_vectors.py"
if($LASTEXITCODE -ne 0){throw 'Vector generation failed'}
$run=Join-Path $root "build/sim/$Tag"
New-Item -ItemType Directory -Force "$run/model","$root/logs" | Out-Null
Copy-Item "$root/sim/auto_vectors/*.hex" -Destination $run -Force
Copy-Item "$root/model/*.hex" -Destination "$run/model" -Force
$bin=(Get-FpgaVivadoBin)
Push-Location $run
try {
 $sources=@(Get-RtlSources -Root $root)+@("$root/sim/tb_plate_auto_chain.sv")
 $hashes=@($sources|ForEach-Object {Get-FileHash -LiteralPath $_ -Algorithm SHA256}|Select-Object Path,Hash)
 $hashes|ConvertTo-Json|Set-Content -Encoding UTF8 "$root/logs/${Tag}_sources.json"
 & "$bin/xvlog.bat" --sv @sources 2>&1 | Tee-Object "$root/logs/${Tag}_compile.log"
 if($LASTEXITCODE -ne 0){throw 'Compile failed'}
 & "$bin/xelab.bat" tb_plate_auto_chain -s auto_chain_snapshot 2>&1 | Tee-Object "$root/logs/${Tag}_elaborate.log"
 if($LASTEXITCODE -ne 0){throw 'Elaborate failed'}
 & "$bin/xsim.bat" auto_chain_snapshot -runall 2>&1 | Tee-Object "$root/logs/${Tag}_simulate.log"
 if($LASTEXITCODE -ne 0){throw 'Simulation failed'}
 $log=Get-Content "$root/logs/${Tag}_simulate.log" -Raw
 if($log -notmatch 'PASS tb_plate_auto_chain' -or $log -match '(Fatal:|Error:)'){throw 'Assertions failed'}
 foreach($h in $hashes){if((Get-FileHash -LiteralPath $h.Path -Algorithm SHA256).Hash -ne $h.Hash){throw "Source changed: $($h.Path)"}}
} finally {Pop-Location}
