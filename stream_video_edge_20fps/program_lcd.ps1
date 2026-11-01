param(
 [string]$Vivado='E:\Vivado\2025.1\Vivado\bin\vivado.bat',
 [string]$OutDir='E:\FPGA_Test_Work\edge20fps_control',
 [string]$ArtifactDir=(Join-Path $PSScriptRoot 'artifacts'),
 [switch]$Snapshot=$true
)
$ErrorActionPreference='Stop'
$OutDir=[IO.Path]::GetFullPath($OutDir)
$ArtifactDir=(Resolve-Path -LiteralPath $ArtifactDir).Path
$variant=if($Snapshot){'lcd_top_snapshot'}else{'lcd_top'}
$snapshotFlag=if($Snapshot){'-snapshot'}else{'-no-snapshot'}
# 默认使用已测产物；选用新构建时，显式指定 -ArtifactDir。
foreach($extension in @('bit','ltx')) {
 if(!(Test-Path -LiteralPath (Join-Path $ArtifactDir "$variant.$extension") -PathType Leaf)) {
  throw "Missing artifact: $variant.$extension in $ArtifactDir"
 }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Push-Location $OutDir
try {
 & $Vivado -mode batch -source (Join-Path $PSScriptRoot 'scripts\paired_overview_hardware.tcl') -log (Join-Path $OutDir 'program.log') -journal (Join-Path $OutDir 'program.jou') -tclargs program $variant $snapshotFlag -artifact-dir $ArtifactDir
 $programCode=$LASTEXITCODE
 if($programCode -eq 0){
  & $Vivado -mode batch -source (Join-Path $PSScriptRoot 'scripts\paired_overview_hardware.tcl') -log (Join-Path $OutDir 'physical.log') -journal (Join-Path $OutDir 'physical.jou') -tclargs physical $snapshotFlag -artifact-dir $ArtifactDir
  $programCode=$LASTEXITCODE
 }
}finally{Pop-Location}
exit $programCode
