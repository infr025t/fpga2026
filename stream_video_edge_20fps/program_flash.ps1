param(
 [ValidateSet('Prepare','Backup','Program')][string]$Action='Prepare',
 [string]$Vivado='E:\Vivado\2025.1\Vivado\bin\vivado.bat',
 [string]$ArtifactDir=(Join-Path $PSScriptRoot 'artifacts'),
 [string]$OutDir='E:\FPGA_Test_Work\edge20fps_flash',
 [string]$RestoreArtifactDir=(Join-Path $PSScriptRoot 'artifacts'),
 [string]$Part='mx25l3273f-spi-x1_x2_x4',
 [string]$TargetSerial='210183BCBF83A'
)
$ErrorActionPreference='Stop'
$ArtifactDir=(Resolve-Path -LiteralPath $ArtifactDir).Path
$RestoreArtifactDir=(Resolve-Path -LiteralPath $RestoreArtifactDir).Path
$OutDir=[IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# Prepare 只生成 MCS；Backup/Program 才连接硬件，结束后恢复已测 RAM 程序。
Push-Location $OutDir
try {
 & $Vivado -mode batch -source (Join-Path $PSScriptRoot 'scripts\flash_lcd.tcl') -log (Join-Path $OutDir "$($Action.ToLower()).log") -journal (Join-Path $OutDir "$($Action.ToLower()).jou") -tclargs $Action.ToLower() $ArtifactDir $OutDir $RestoreArtifactDir $Part $TargetSerial
 $flashCode=$LASTEXITCODE
} finally {Pop-Location}
exit $flashCode
