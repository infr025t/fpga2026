param([string]$Vivado='E:\Vivado\2025.1\Vivado\bin\vivado.bat',[string]$OutDir='E:\FPGA_Test_Work\lcd_v04_build',[switch]$Snapshot)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $OutDir
try {
 $snapshotFlag=if($Snapshot){'1'}else{'0'}
 & $Vivado -mode batch -source (Join-Path $PSScriptRoot 'scripts\build_lcd.tcl') -log (Join-Path $OutDir 'build.log') -journal (Join-Path $OutDir 'build.jou') -tclargs $OutDir $snapshotFlag
 $buildCode=$LASTEXITCODE
}finally{Pop-Location}
exit $buildCode
