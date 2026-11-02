param([string]$Vivado='',[string]$OutDir=(Join-Path $PSScriptRoot 'build/release_01'))
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutDir){throw "Build output already exists; choose a new -OutDir: $OutDir"}
. (Join-Path $PSScriptRoot 'config/toolchain.ps1')
$Vivado=Join-Path (Get-FpgaVivadoBin -Override $Vivado) 'vivado.bat'
$previousPython=$env:FPGA_PYTHON
$env:FPGA_PYTHON=Get-FpgaPython
$OutDir=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
New-Item -ItemType Directory $OutDir | Out-Null
Push-Location $PSScriptRoot
try {
 & $Vivado -mode batch -source scripts\build.tcl -log (Join-Path $OutDir build.log) -journal (Join-Path $OutDir build.jou) -tclargs $OutDir --reserved-output
 if($LASTEXITCODE -ne 0){
  $log=Get-Content (Join-Path $OutDir 'build.log') -Raw
  if($log -notmatch 'Timing (max|min) failed' -or !(Test-Path (Join-Path $OutDir 'post_route.dcp'))){throw 'Build failed before timing refinement; inspect build.log'}
  & $Vivado -mode batch -source scripts/refine_timing.tcl -log (Join-Path $OutDir refine.log) -journal (Join-Path $OutDir refine.jou) -tclargs $OutDir
  if($LASTEXITCODE -ne 0){throw 'Timing refinement failed; no verified bitstream produced'}
 }
} finally {Pop-Location; $env:FPGA_PYTHON=$previousPython}
