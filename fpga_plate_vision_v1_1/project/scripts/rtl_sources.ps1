# 构建与仿真共用这一份源清单，避免新增模块后某个测试漏编译。
function Get-RtlSources([string]$Root) {
 $items=Get-Content -LiteralPath (Join-Path $Root 'config/rtl_sources.txt')
 foreach($item in $items){
  if(!$item.Trim() -or $item.StartsWith('#')){continue}
  $path=Join-Path $Root $item
  if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing RTL source: $item"}
  $path
 }
}
