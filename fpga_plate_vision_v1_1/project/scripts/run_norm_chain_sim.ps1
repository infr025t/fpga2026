param([string]$Tag='norm_chain')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$projectRoot=Split-Path -Parent $PSScriptRoot
. "$projectRoot/scripts/rtl_sources.ps1"
# 原始输入缺失时只使用逐文件校验的历史冻结向量，不宣称重新生成。
$originalInputs=Join-Path $projectRoot '../evidence/baseline/reports/norm_reference/rtl_vectors/manifest.json'
if(Test-Path -LiteralPath $originalInputs){
 & (Get-FpgaPython) "$projectRoot/scripts/make_norm_chain_vectors.py"
 if($LASTEXITCODE -ne 0){throw 'Golden vector generation failed'}
} else {
 $frozen=Get-Content -LiteralPath "$projectRoot/../evidence/baseline/norm_chain_vectors_sha256.json" -Raw | ConvertFrom-Json
 foreach($entry in $frozen.files){
  $path=Join-Path $projectRoot $entry.path
  if(!(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256){throw "Frozen normalization vector missing or changed: $path"}
 }
 Write-Host 'Using verified historical frozen norm_chain_vectors; original generation inputs unavailable; no vectors regenerated.'
}
$runDir=Join-Path $projectRoot "build/sim/$Tag"
New-Item -ItemType Directory -Force "$runDir/model","$projectRoot/logs" | Out-Null
Copy-Item "$projectRoot/sim/norm_chain_vectors/*.hex" -Destination $runDir -Force
Copy-Item -LiteralPath "$projectRoot/model/weights.hex","$projectRoot/model/biases.hex" -Destination "$runDir/model" -Force
$vivadoBin=(Get-FpgaVivadoBin)
Push-Location $runDir
try {
 $sources=@(Get-RtlSources -Root $projectRoot)+@("$projectRoot/sim/tb_norm_chain.sv")
 & "$vivadoBin/xvlog.bat" --sv @sources 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_compile.log"
 if($LASTEXITCODE -ne 0){throw 'Real normalization chain compilation failed'}
 & "$vivadoBin/xelab.bat" tb_norm_chain -s tb_norm_chain_snapshot 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_elaborate.log"
 if($LASTEXITCODE -ne 0){throw 'Real normalization chain elaboration failed'}
 & "$vivadoBin/xsim.bat" tb_norm_chain_snapshot -runall 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_simulate.log"
 if($LASTEXITCODE -ne 0){throw 'Real normalization chain simulation failed'}
 $resultText=Get-Content "$projectRoot/logs/${Tag}_simulate.log" -Raw
 if($resultText -notmatch 'PASS tb_norm_chain' -or $resultText -match '(Fatal:|Error:)'){throw 'Real normalization chain assertions did not pass'}
} finally {Pop-Location}
