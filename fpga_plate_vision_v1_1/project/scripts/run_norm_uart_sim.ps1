param([string]$Tag='norm_uart')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$projectRoot=Split-Path -Parent $PSScriptRoot
. "$projectRoot/scripts/rtl_sources.ps1"
$runDir=Join-Path $projectRoot "build/sim/$Tag"
New-Item -ItemType Directory -Force $runDir,"$projectRoot/logs" | Out-Null
$vivadoBin=(Get-FpgaVivadoBin)
Push-Location $runDir
try {
 $sources=@(Get-RtlSources -Root $projectRoot)+@("$projectRoot/sim/tb_norm_uart_bridge.sv")
 & "$vivadoBin/xvlog.bat" --sv @sources 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_compile.log"
 if($LASTEXITCODE -ne 0){throw 'Normalization UART compilation failed'}
 & "$vivadoBin/xelab.bat" tb_norm_uart_bridge -s tb_norm_uart_snapshot 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_elaborate.log"
 if($LASTEXITCODE -ne 0){throw 'Normalization UART elaboration failed'}
 & "$vivadoBin/xsim.bat" tb_norm_uart_snapshot -runall 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_simulate.log"
 if($LASTEXITCODE -ne 0){throw 'Normalization UART simulation failed'}
 $resultText=Get-Content "$projectRoot/logs/${Tag}_simulate.log" -Raw
 if($resultText -notmatch 'PASS tb_norm_uart_bridge' -or $resultText -match '(Fatal:|Error:)'){throw 'Normalization UART assertions did not pass'}
} finally {Pop-Location}
