param([string]$Vivado='E:\Vivado\2025.1\Vivado\bin\vivado.bat',[string]$OutDir='E:\FPGA_Test_Work\edge20fps_control')
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $OutDir
try {
 & $Vivado -mode batch -source (Join-Path $PSScriptRoot 'scripts\paired_overview_hardware.tcl') -log (Join-Path $OutDir 'program.log') -journal (Join-Path $OutDir 'program.jou') -tclargs program lcd_top_snapshot -snapshot
 $programCode=$LASTEXITCODE
 if($programCode -eq 0){
  & $Vivado -mode batch -source (Join-Path $PSScriptRoot 'scripts\paired_overview_hardware.tcl') -log (Join-Path $OutDir 'physical.log') -journal (Join-Path $OutDir 'physical.jou') -tclargs physical -snapshot
  $programCode=$LASTEXITCODE
 }
}finally{Pop-Location}
exit $programCode
