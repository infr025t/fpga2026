param([string]$Tag='auto_split_scene')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
& (Get-FpgaPython) "$root/scripts/make_auto_split_vectors.py"
if($LASTEXITCODE -ne 0){throw 'Vector generation failed'}
$run=Join-Path $root "build/sim/$Tag"
New-Item -ItemType Directory -Force "$run/model","$root/logs" | Out-Null
Copy-Item "$root/sim/auto_split_vectors/*.hex" -Destination $run -Force
Copy-Item "$root/model/*.hex" -Destination "$run/model" -Force
$bin=(Get-FpgaVivadoBin)
Push-Location $run
try {
 $sources=@(Get-RtlSources -Root $root)+@("$root/sim/tb_auto_split_scene.sv")
 $evidence=$sources+@("$root/scripts/make_auto_split_vectors.py","$root/pc/auto_protocol.py","$root/pc/plate_locator.py","$root/pc/segment_ref.py","$root/pc/norm_ref.py","$root/pc/integer_cnn.py")+@(Get-ChildItem "$root/sim/auto_split_vectors/*","$root/model/*.hex" -File | Select-Object -ExpandProperty FullName)
 $hashes=@($evidence|ForEach-Object {Get-FileHash -LiteralPath $_ -Algorithm SHA256}|Select-Object Path,Hash)
 $hashes|ConvertTo-Json|Set-Content -Encoding UTF8 "$root/logs/${Tag}_sources.json"
 & "$bin/xvlog.bat" --sv @sources 2>&1 | Tee-Object "$root/logs/${Tag}_compile.log"
 if($LASTEXITCODE -ne 0){throw 'Compile failed'}
 & "$bin/xelab.bat" tb_auto_split_scene -s auto_split_scene_snapshot 2>&1 | Tee-Object "$root/logs/${Tag}_elaborate.log"
 if($LASTEXITCODE -ne 0){throw 'Elaborate failed'}
 & "$bin/xsim.bat" auto_split_scene_snapshot -runall 2>&1 | Tee-Object "$root/logs/${Tag}_simulate.log"
 if($LASTEXITCODE -ne 0){throw 'Simulation failed'}
 $log=Get-Content "$root/logs/${Tag}_simulate.log" -Raw
 if($log -notmatch 'PASS tb_auto_split_scene' -or $log -match '(Fatal:|Error:)'){throw 'Assertions failed'}
 foreach($h in $hashes){if((Get-FileHash -LiteralPath $h.Path -Algorithm SHA256).Hash -ne $h.Hash){throw "Source changed: $($h.Path)"}}
 & (Get-FpgaPython) "$root/scripts/make_auto_split_vectors.py" --check-wire "$run/auto_wire.bin" 2>&1 | Tee-Object "$root/logs/${Tag}_uart_verify.log"
 if($LASTEXITCODE -ne 0){throw 'Current-scene UART verification failed'}
 "PASS stable_sources $Tag" | Tee-Object -Append "$root/logs/${Tag}_simulate.log"
} finally {Pop-Location}

