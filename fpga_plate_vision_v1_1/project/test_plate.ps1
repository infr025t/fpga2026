param(
 [Parameter(Mandatory=$true)][string]$Label,
 [int]$Frames=100,
 [string]$Roi='26,35,158,87',
 [ValidateSet(0,180)][int]$Rotation=0,
 [switch]$Invert,
 [string]$Truth=''
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "config/toolchain.ps1")
if($Label -notmatch '^[A-Za-z0-9_-]+$'){throw 'Label must be a new safe name'}
if($Frames -le 0){throw 'Frames must be positive'}
$roiValues=$Roi.Split(',')
if($roiValues.Length -ne 4){throw 'ROI requires x0,y0,x1,y1'}
$vivado=(Join-Path (Get-FpgaVivadoBin) 'vivado.bat')
$python=(Get-FpgaPython)
Push-Location $PSScriptRoot
try {
 New-Item -ItemType Directory -Force logs | Out-Null
 & $vivado -mode batch -source scripts/hardware.tcl -log "logs/${Label}_camera.log" -journal "logs/${Label}_camera.jou" -tclargs camera
 if($LASTEXITCODE -ne 0){throw 'Cannot select camera diagnostic'}
 & $python pc_diag/record_pairs.py --label $Label --frames $Frames --timeout 15
 if($LASTEXITCODE -ne 0){throw 'Image capture failed'}
 & $vivado -mode batch -source scripts/hardware.tcl -log "logs/${Label}_norm.log" -journal "logs/${Label}_norm.jou" -tclargs cnn
 if($LASTEXITCODE -ne 0){throw 'Cannot select normalization diagnostic'}
 $extra=@()
 if($Invert){$extra+='--invert'}
 if($Truth){$extra+=@('--truth',$Truth)}
 & $python pc/verify_segment_board.py --frames "reports/uart_pairs/$Label/frames" --out "reports/board/$Label" --limit $Frames --roi @roiValues --rotation $Rotation @extra
 if($LASTEXITCODE -ne 0){throw 'Board segmentation comparison failed'}
} finally {
 # 退出时交还实体开关；不下载旧程序，不写Flash。
 try {
  & $vivado -mode batch -source scripts/hardware.tcl -log "logs/${Label}_physical.log" -journal "logs/${Label}_physical.jou" -tclargs physical
  if($LASTEXITCODE -ne 0){throw 'Physical switch control restore failed; inspect the physical log'}
 } finally {Pop-Location}
}
