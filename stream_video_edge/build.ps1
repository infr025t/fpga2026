param([string]$Vivado='E:\Vivado\2025.1\Vivado\bin\vivado.bat',[string]$OutDir='E:\FPGA_Test_Work\gaussian_uart_build')
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Push-Location $OutDir
try {
 & $Vivado -mode batch -source (Join-Path $PSScriptRoot 'scripts\build.tcl') -log (Join-Path $OutDir 'build.log') -journal (Join-Path $OutDir 'build.jou') -tclargs $OutDir
 $buildExitCode=$LASTEXITCODE
} finally { Pop-Location }
exit $buildExitCode
