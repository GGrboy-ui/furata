# run_oss.ps1 - lint and Icarus regression using an OSS CAD Suite install.
# Usage with Icarus Verilog: powershell -ExecutionPolicy Bypass -File sim\run_oss.ps1 -OssCadSuite G:\iverilog -SkipLint
# Omit -SkipLint when the selected tool directory also contains Verilator.
[CmdletBinding()]
param(
  [string[]]$Tb,
  [string]$OssCadSuite = $env:OSS_CAD_SUITE,
  [switch]$SkipLint
)
$ErrorActionPreference='Stop'
$ws=Split-Path -Parent $PSScriptRoot
$rtlDir=Join-Path $ws 'src\rtl'; $simDir=Join-Path $ws 'sim'; $outRoot=Join-Path $ws 'build\oss'
New-Item -ItemType Directory -Force $outRoot | Out-Null

function Resolve-Tool([string]$name) {
  if ($OssCadSuite) {
    $candidates=@(
      (Join-Path $OssCadSuite "bin\$name.exe"),
      (Join-Path $OssCadSuite "$name.exe"),
      (Join-Path $OssCadSuite "bin\$name")
    )
    foreach($c in $candidates){ if(Test-Path -LiteralPath $c){ return (Resolve-Path $c).Path } }
  }
  $cmd=Get-Command $name -ErrorAction SilentlyContinue
  if($cmd){ return $cmd.Source }
  return $null
}
$verilator=Resolve-Tool 'verilator'; $iverilog=Resolve-Tool 'iverilog'; $vvp=Resolve-Tool 'vvp'
if(!$iverilog -or !$vvp){
  $msg="OSS CAD Suite tools not found. Pass -OssCadSuite <suite> or set OSS_CAD_SUITE; expected bin\iverilog.exe and bin\vvp.exe."
  $msg | Set-Content (Join-Path $outRoot 'regression_report.txt')
  Write-Error $msg
  exit 1
}
if(!$Tb -or $Tb.Count -eq 0){ $Tb=@(Get-ChildItem $simDir -Filter 'tb_*.v' -File | % BaseName | Sort-Object) }
if($Tb.Count -eq 0){ throw 'no sim\tb_*.v testbenches found' }
$rtlSrc=@(Get-ChildItem $rtlDir -Filter '*.v' -File | % FullName)
$boardDir=Join-Path $ws 'src\board'
$boardSrc=@(Get-ChildItem $boardDir -Filter '*.v' -File -ErrorAction SilentlyContinue | % FullName)
if($rtlSrc.Count -eq 0){ throw 'no rtl\*.v sources found' }
$failed=@(); $missing=@()
if(!$SkipLint){
  if(!$verilator){
    $msg='Verilator not found; lint is mandatory unless a valid OSS CAD Suite path is supplied.'
    $msg | Set-Content (Join-Path $outRoot 'regression_report.txt')
    Write-Error $msg
    exit 1
  }
  $lintSrc=@($rtlSrc+$boardSrc)
  Write-Host "=== [lint] verilator over $($lintSrc.Count) design file(s) ==="
  & $verilator --lint-only -sv -Wall -Wno-fatal -Wno-MULTITOP @lintSrc
  $lintCode=$LASTEXITCODE
  if($lintCode -ne 0){ $failed+='lint' } else { Write-Host 'lint: clean (exit=0)' }
}
foreach($name in $Tb){
  $tbFile=Join-Path $simDir "$name.v"
  if(!(Test-Path -LiteralPath $tbFile)){ Write-Host "[MISSING] $name"; $missing+=$name; continue }
  $outDir=Join-Path $outRoot $name; New-Item -ItemType Directory -Force $outDir | Out-Null; $vvpFile=Join-Path $outDir "$name.vvp"
  Write-Host "`n=== [sim] $name ==="
  $sources=@($rtlSrc)
  if($name -like 'tb_acg720_*'){ $sources += $boardSrc }
  $sources += $tbFile
  & $iverilog -g2012 -s $name -o $vvpFile @sources 2>&1 | % { Write-Host "  $_" }
  if($LASTEXITCODE -ne 0){ Write-Host '  compile FAILED'; $failed+=$name; continue }
  Push-Location $outDir; try { $runOutput=@(& $vvp $vvpFile 2>&1); $runCode=$LASTEXITCODE; $runOutput | % { Write-Host "  $_" } } finally { Pop-Location }
  $runBad=@($runOutput | ? { $_ -match 'TEST FAILED|FAIL:|ERROR:|%Error' })
  if($runCode -ne 0 -or $runBad.Count -gt 0){ $failed+=$name; Write-Host "  RESULT: FAIL (exit=$runCode)" }
  elseif(@(Get-ChildItem $outDir -Filter '*.vcd' -File).Count -gt 0){ Write-Host '  RESULT: PASS' }
  else { $failed+=$name; Write-Host '  RESULT: FAIL (no VCD/test completion)' }
}
$passed=$Tb.Count-$failed.Count-$missing.Count
$report=Join-Path $outRoot 'regression_report.txt'; New-Item -ItemType Directory -Force $outRoot | Out-Null
@("ACG720 FPGA regression $(Get-Date -Format s)","requested=$($Tb -join ',')","passed=$passed","failed=$($failed -join ',')","missing=$($missing -join ',')","waveforms=$outRoot") | Set-Content $report
Write-Host "`n=== summary: $passed / $($Tb.Count) testbench(es) passed ==="
if($missing.Count){ Write-Host "missing: $($missing -join ', ')" }
if($failed.Count){ Write-Host "failed: $($failed -join ', ')"; exit 1 }
if($missing.Count){ exit 1 }
exit 0
