param([switch]$Internal)
$receiver=Join-Path $PSScriptRoot 'pc\receive.py'
if ($Internal) { & 'E:\Python\python.exe' -B $receiver --source internal }
else { & 'E:\Python\python.exe' -B $receiver --source camera }
exit $LASTEXITCODE
