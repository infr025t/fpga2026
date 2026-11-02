param([string]$Tag = 'chain')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot/scripts/rtl_sources.ps1"
$runDir = Join-Path $projectRoot "build/sim/$Tag"
New-Item -ItemType Directory -Force "$runDir/model" | Out-Null
New-Item -ItemType Directory -Force "$projectRoot/logs" | Out-Null
Copy-Item -LiteralPath "$projectRoot/model/weights.hex", "$projectRoot/model/biases.hex" -Destination "$runDir/model" -Force
Copy-Item -LiteralPath "$projectRoot/sim/vectors_input.hex", "$projectRoot/sim/vectors_scores.hex" -Destination $runDir -Force
$vivadoBin = (Get-FpgaVivadoBin)
Push-Location $runDir
try {
 $sources=@(Get-RtlSources -Root $projectRoot)+@("$projectRoot/sim/tb_cnn_chain.sv")
    & "$vivadoBin/xvlog.bat" --sv @sources 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_compile.log"
    if ($LASTEXITCODE -ne 0) { throw 'Chain compilation failed' }
    & "$vivadoBin/xelab.bat" tb_cnn_chain -s tb_cnn_chain_snapshot 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_elaborate.log"
    if ($LASTEXITCODE -ne 0) { throw 'Chain elaboration failed' }
    & "$vivadoBin/xsim.bat" tb_cnn_chain_snapshot -runall 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_simulate.log"
    if ($LASTEXITCODE -ne 0) { throw 'Chain simulation process failed' }
    $resultText = Get-Content "$projectRoot/logs/${Tag}_simulate.log" -Raw
    if ($resultText -notmatch 'PASS tb_cnn_chain' -or $resultText -match '(Fatal:|Error:)') { throw 'Chain assertions did not pass' }
} finally { Pop-Location }
