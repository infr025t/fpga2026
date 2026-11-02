param([int]$Cases=12,[switch]$SmokeOnly,[string]$BuildName='cnn')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$root=Split-Path -Parent $PSScriptRoot
. "$root/scripts/rtl_sources.ps1"
$build=Join-Path $root "build/sim/$BuildName"
New-Item -ItemType Directory -Force -Path $build | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $build 'model') | Out-Null
if (Test-Path (Join-Path $root 'model/weights.hex')) {
 Copy-Item (Join-Path $root 'model/*.hex') (Join-Path $build 'model') -Force
}
if (!$SmokeOnly) {
 Copy-Item (Join-Path $root 'sim/vectors_input.hex') $build -Force
 Copy-Item (Join-Path $root 'sim/vectors_scores.hex') $build -Force
}
$vivado=(Get-FpgaVivadoBin)
Push-Location $build
try {
 & "$vivado/xvlog.bat" -sv @(Get-RtlSources -Root $root) "$root/sim/tb_cnn_core.sv" 2>&1 | Tee-Object compile_console.log
 if ($LASTEXITCODE -ne 0) {throw 'xvlog failed'}
 $smoke=[int]$SmokeOnly.IsPresent
 @("-generic_top NUM_CASES=$Cases","-generic_top SMOKE_ONLY=$smoke") | Set-Content elaborate.options -Encoding ascii
 & "$vivado/xelab.bat" tb_cnn_core -s cnn_snapshot -f elaborate.options 2>&1 | Tee-Object elaborate_console.log
 if ($LASTEXITCODE -ne 0) {throw 'xelab failed'}
 & "$vivado/xsim.bat" cnn_snapshot -runall 2>&1 | Tee-Object simulate_console.log
 if ($LASTEXITCODE -ne 0) {throw 'xsim failed'}
 $log=Get-Content simulate_console.log -Raw
 if ($log -match 'Fatal:|Error:' -or $log -notmatch 'PASS (cnn_core all|smoke reset/start/abort)') {throw 'CNN self-check did not pass'}
} finally {Pop-Location}
