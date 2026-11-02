$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. "$root/config/toolchain.ps1"
. "$root/scripts/rtl_sources.ps1"
$python=Get-FpgaPython
$bin=Get-FpgaVivadoBin
& $python "$root/scripts/make_white_character_vectors.py"
if($LASTEXITCODE){throw 'Vector generation failed'}
$run=Join-Path $root 'build/sim_white_characters'
if(Test-Path $run){throw 'Choose a clean simulation directory; existing evidence is preserved'}
New-Item -ItemType Directory -Force "$run/model" | Out-Null
Copy-Item "$root/sim/white_character_vectors/*.hex" $run
Copy-Item "$root/model/*.hex" "$run/model"
Push-Location $run
try {
 & "$bin/xvlog.bat" -sv @(Get-RtlSources -Root $root) "$root/sim/tb_white_character_scene.sv"
 if($LASTEXITCODE){throw 'Compile failed'}
 & "$bin/xelab.bat" tb_white_character_scene -s white_characters
 if($LASTEXITCODE){throw 'Elaboration failed'}
 & "$bin/xsim.bat" white_characters -runall -log white_characters.log
 if($LASTEXITCODE -or !(Select-String white_characters.log -Pattern 'PASS tb_white_character_scene' -Quiet)){throw 'White-character simulation failed'}
 & $python "$root/pc/observe_auto.py" --wire "$run/auto_wire.bin" --frames 2 --out "$run/replay"
 if($LASTEXITCODE){throw 'White-character UART reference comparison failed'}
} finally {Pop-Location}
