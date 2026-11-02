param([int]$Frames=20,[int]$Timeout=30,[string]$Truth='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot "config/toolchain.ps1")
$out=Join-Path $PSScriptRoot ('reports/observation_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$arguments=@("$PSScriptRoot/pc/observe_auto.py",'--frames',"$Frames",'--timeout',"$Timeout",'--out',$out)
if($Truth){$arguments+=@('--truth',$Truth)}
& (Get-FpgaPython) @arguments
if($LASTEXITCODE -ne 0){throw "Observation did not fully pass. Evidence: $out"}
Write-Host "Evidence: $out"
