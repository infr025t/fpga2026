param(
 [string]$Vivado='E:\Vivado\2025.1\Vivado\bin\vivado.bat',
 [string]$OutDir='E:\FPGA_Test_Work\edge20fps_build',
 [switch]$Snapshot=$true,
 [ValidateRange(0,2147483647)][int]$StatFrames=0
)
$ErrorActionPreference='Stop'
$OutDir=[IO.Path]::GetFullPath($OutDir)
# 新构建保存在独立目录，不覆盖 artifacts 中已验证的版本。
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $OutDir
try {
 $snapshotFlag=if($Snapshot){'1'}else{'0'}
 & $Vivado -mode batch -source (Join-Path $PSScriptRoot 'scripts\build_lcd.tcl') -log (Join-Path $OutDir 'build.log') -journal (Join-Path $OutDir 'build.jou') -tclargs $OutDir $snapshotFlag $StatFrames
 $buildCode=$LASTEXITCODE
}finally{Pop-Location}
exit $buildCode
