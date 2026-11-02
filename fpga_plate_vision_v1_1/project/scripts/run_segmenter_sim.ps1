param([string]$Tag='segmenter',[string]$Manifest='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$projectRoot=Split-Path -Parent $PSScriptRoot
. "$projectRoot/scripts/rtl_sources.ps1"
$runDir=Join-Path $projectRoot "reports/segment_rtl/$Tag"
New-Item -ItemType Directory -Force $runDir | Out-Null
$vivadoBin=(Get-FpgaVivadoBin)
Push-Location $runDir
try {
 & "$vivadoBin/xvlog.bat" --sv @(Get-RtlSources -Root $projectRoot) "$projectRoot/sim/tb_char_segmenter.sv" 2>&1 | Tee-Object 'compile.log'
 if($LASTEXITCODE -ne 0){throw 'Segmenter compilation failed'}
 & "$vivadoBin/xelab.bat" tb_char_segmenter -s segmenter_snapshot 2>&1 | Tee-Object 'elaborate.log'
 if($LASTEXITCODE -ne 0){throw 'Segmenter elaboration failed'}
 $simArgs=@('segmenter_snapshot','-runall')
 if($Manifest){
  $manifestPath=(Resolve-Path $Manifest).Path.Replace('\','/')
  $vectorRoot=(Split-Path -Parent $manifestPath).Replace('\','/')
  @("-testplusarg MANIFEST=$manifestPath","-testplusarg VECTOR_ROOT=$vectorRoot") | Set-Content -Encoding ascii 'plusargs.txt'
  $simArgs+=@('-f','plusargs.txt')
 }
 & "$vivadoBin/xsim.bat" @simArgs 2>&1 | Tee-Object 'simulate.log'
 if($LASTEXITCODE -ne 0){throw 'Segmenter simulation failed'}
 $result=Get-Content 'simulate.log' -Raw
 if($result -notmatch 'PASS tb_char_segmenter' -or $result -match '(Fatal:|Error:)'){throw 'Segmenter assertions failed'}
} finally {Pop-Location}
