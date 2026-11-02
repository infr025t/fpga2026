param([ValidateSet('', 'python', 'vivado_bin')][string]$Tool='')
# 统一发现Python/Vivado；显式配置无效时立即报错。
function Get-FpgaPython {
    param([string]$Override='')
    $explicit=$Override
    if(!$explicit){$explicit=$env:FPGA_PYTHON}
    if($explicit){
        if(!(Test-Path -LiteralPath $explicit -PathType Leaf)){throw "FPGA_PYTHON must name an existing Python executable: $explicit"}
        return (Resolve-Path -LiteralPath $explicit).Path
    }
    foreach($name in @('python','python3')){
        $command=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if($command -and $command.Source -notmatch 'WindowsApps'){
            return $command.Source
        }
    }
    $launcher=Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if($launcher){
        $resolved=& $launcher.Source -3 -c 'import sys; print(sys.executable)' 2>$null
        if($LASTEXITCODE -eq 0 -and $resolved -and (Test-Path -LiteralPath $resolved -PathType Leaf)){return $resolved}
    }
    $patterns=@()
    if($env:LOCALAPPDATA){$patterns+=Join-Path $env:LOCALAPPDATA 'Programs/Python/Python*/python.exe'}
    foreach($drive in Get-PSDrive -PSProvider FileSystem){
        foreach($relative in @('Python/python.exe','Python*/python.exe','Program Files/Python*/python.exe')){
            $patterns+=Join-Path $drive.Root $relative
        }
    }
    foreach($pattern in $patterns){
        $candidate=Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if($candidate){return $candidate.FullName}
    }
    throw 'Python was not found. Set FPGA_PYTHON to the full path of python.exe.'
}

function Get-FpgaVivadoBin {
    param([string]$Override='')
    $explicit=$Override
    if(!$explicit){$explicit=$env:FPGA_VIVADO_BIN}
    if($explicit){
        if(Test-Path -LiteralPath $explicit -PathType Leaf){$explicit=Split-Path -Parent $explicit}
        if(!(Test-Path -LiteralPath ([System.IO.Path]::Combine($explicit, 'vivado.bat')) -PathType Leaf)){
            throw "Vivado was not found in $explicit. Set FPGA_VIVADO_BIN to the Vivado bin directory."
        }
        return (Resolve-Path -LiteralPath $explicit).Path
    }
    if($env:XILINX_VIVADO){
        $candidate=Join-Path $env:XILINX_VIVADO 'bin'
        if(Test-Path -LiteralPath (Join-Path $candidate 'vivado.bat') -PathType Leaf){return $candidate}
    }
    $command=Get-Command vivado.bat -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if($command){return Split-Path -Parent $command.Source}
    foreach($drive in Get-PSDrive -PSProvider FileSystem){
        foreach($relative in @('Vivado/*/Vivado/bin/vivado.bat','Vivado/*/bin/vivado.bat','Xilinx/Vivado/*/bin/vivado.bat','Xilinx/*/Vivado/bin/vivado.bat','AMDDesignTools/*/Vivado/bin/vivado.bat')){
            $candidate=Get-ChildItem -Path (Join-Path $drive.Root $relative) -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
            if($candidate){return $candidate.DirectoryName}
        }
    }
    throw 'Vivado was not found. Set FPGA_VIVADO_BIN to its bin directory.'
}

if($Tool -eq 'python'){Get-FpgaPython}
elseif($Tool -eq 'vivado_bin'){Get-FpgaVivadoBin}
