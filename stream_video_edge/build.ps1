$ErrorActionPreference='Stop'
$vivadoPath='E:\Vivado\2025.1\Vivado\bin\vivado.bat'
$buildRoot='E:\FPGA_Test_Work\edge_v03_work'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
Push-Location $buildRoot
try {
 & $vivadoPath -mode batch -source (Join-Path $PSScriptRoot 'scripts\build.tcl') -log (Join-Path $buildRoot 'build.log') -journal (Join-Path $buildRoot 'build.jou')
 $buildExitCode=$LASTEXITCODE
} finally { Pop-Location }
exit $buildExitCode
