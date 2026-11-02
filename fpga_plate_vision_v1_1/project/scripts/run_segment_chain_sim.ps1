param([string]$Tag='segment_chain')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "../config/toolchain.ps1")
$projectRoot=Split-Path -Parent $PSScriptRoot
. "$projectRoot/scripts/rtl_sources.ps1"
& (Get-FpgaPython) "$projectRoot/scripts/make_segment_chain_vectors.py"
if($LASTEXITCODE -ne 0){throw 'Golden vector generation failed'}
$runDir=Join-Path $projectRoot "build/sim/$Tag"
New-Item -ItemType Directory -Force "$runDir/model","$projectRoot/logs" | Out-Null
Copy-Item "$projectRoot/sim/segment_chain_vectors/*.hex" -Destination $runDir -Force
Copy-Item -LiteralPath "$projectRoot/model/weights.hex","$projectRoot/model/biases.hex" -Destination "$runDir/model" -Force
$vivadoBin=(Get-FpgaVivadoBin)
Push-Location $runDir
try {
 $sources=@(Get-RtlSources -Root $projectRoot)+@("$projectRoot/sim/tb_segment_chain.sv")
 $evidenceFiles=$sources+@("$projectRoot/model/weights.hex","$projectRoot/model/biases.hex","$projectRoot/sim/segment_chain_vectors/manifest.json")
 $sourceHashes=@($evidenceFiles | ForEach-Object {Get-FileHash -Algorithm SHA256 -LiteralPath $_} | Select-Object Path,Hash)
 $sourceHashes | ConvertTo-Json | Set-Content -Encoding UTF8 "$projectRoot/logs/${Tag}_sources.json"
 & "$vivadoBin/xvlog.bat" --sv @sources 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_compile.log"
 if($LASTEXITCODE -ne 0){throw 'Real segmentation chain compilation failed'}
 & "$vivadoBin/xelab.bat" tb_segment_chain -s tb_segment_chain_snapshot 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_elaborate.log"
 if($LASTEXITCODE -ne 0){throw 'Real segmentation chain elaboration failed'}
 & "$vivadoBin/xsim.bat" tb_segment_chain_snapshot -runall 2>&1 | Tee-Object "$projectRoot/logs/${Tag}_simulate.log"
 if($LASTEXITCODE -ne 0){throw 'Real segmentation chain simulation failed'}
 $resultText=Get-Content "$projectRoot/logs/${Tag}_simulate.log" -Raw
 if($resultText -notmatch 'PASS tb_segment_chain' -or $resultText -match '(Fatal:|Error:)'){throw 'Real segmentation chain assertions did not pass'}
 foreach($entry in $sourceHashes){
  if((Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Path).Hash -ne $entry.Hash){
   "Error: Source changed during simulation: $($entry.Path); rerun against stable files" | Tee-Object -Append "$projectRoot/logs/${Tag}_simulate.log"
   throw 'Source changed during simulation; numerical result cannot establish current source verification'
  }
 }
 "PASS stable_sources $Tag" | Tee-Object -Append "$projectRoot/logs/${Tag}_simulate.log"
} finally {Pop-Location}
