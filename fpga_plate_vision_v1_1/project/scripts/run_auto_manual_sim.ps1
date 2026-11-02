param([string]$Tag='auto_manual_chain')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$projectRoot=Split-Path -Parent $PSScriptRoot
. "$projectRoot/scripts/rtl_sources.ps1"
# 使用已冻结的原人工链黄金向量，不重新生成或改动旧文件。
$runDir=Join-Path $projectRoot "build/sim/$Tag"
New-Item -ItemType Directory -Force "$runDir/model","$projectRoot/logs" | Out-Null
Copy-Item "$projectRoot/sim/segment_chain_vectors/*.hex" -Destination $runDir -Force
Copy-Item -LiteralPath "$projectRoot/model/weights.hex","$projectRoot/model/biases.hex" -Destination "$runDir/model" -Force
$vivadoBin=(Get-FpgaVivadoBin)
Push-Location $runDir
try {
 $sources=@(Get-RtlSources -Root $projectRoot)+@("$projectRoot/sim/tb_auto_manual_chain.sv")
 $evidenceFiles=$sources+@("$projectRoot/model/weights.hex","$projectRoot/model/biases.hex","$projectRoot/sim/segment_chain_vectors/manifest.json")
 $sourceHashes=@($evidenceFiles | ForEach-Object {Get-FileHash -Algorithm SHA256 -LiteralPath $_} | Select-Object Path,Hash)
 $sourceHashes | ConvertTo-Json | Set-Content -Encoding UTF8 "$projectRoot/logs/${Tag}_sources.json"
 & "$vivadoBin/xvlog.bat" --sv @sources 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_compile.log"
 if($LASTEXITCODE -ne 0){throw 'Real segmentation chain compilation failed'}
 & "$vivadoBin/xelab.bat" tb_auto_manual_chain -s tb_auto_manual_chain_snapshot 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_elaborate.log"
 if($LASTEXITCODE -ne 0){throw 'Real segmentation chain elaboration failed'}
 & "$vivadoBin/xsim.bat" tb_auto_manual_chain_snapshot -runall 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_simulate.log"
 if($LASTEXITCODE -ne 0){throw 'Real segmentation chain simulation failed'}
 $resultText=Get-Content "$projectRoot/logs/${Tag}_simulate.log" -Raw
 if($resultText -notmatch 'PASS tb_auto_manual_chain' -or $resultText -match '(Fatal:|Error:)'){throw 'Real segmentation chain assertions did not pass'}
 foreach($entry in $sourceHashes){
  if((Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Path).Hash -ne $entry.Hash){
   "Error: Source changed during simulation: $($entry.Path); rerun against stable files" | Tee-Object -Append "$projectRoot/logs/${Tag}_simulate.log"
   throw 'Source changed during simulation; numerical result cannot establish current source verification'
  }
 }
 "PASS stable_sources $Tag" | Tee-Object -Append "$projectRoot/logs/${Tag}_simulate.log"
} finally {Pop-Location}

