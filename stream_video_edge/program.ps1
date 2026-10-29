$ErrorActionPreference='Stop'
$workRoot='E:\FPGA_Test_Work\edge_v03_work'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
Push-Location $workRoot
try {
 & 'E:\Vivado\2025.1\Vivado\bin\vivado.bat' -mode batch -source (Join-Path $PSScriptRoot 'scripts\program.tcl') -log (Join-Path $workRoot 'stable_program.log') -journal (Join-Path $workRoot 'stable_program.jou')
 $programExitCode=$LASTEXITCODE
} finally { Pop-Location }
exit $programExitCode
