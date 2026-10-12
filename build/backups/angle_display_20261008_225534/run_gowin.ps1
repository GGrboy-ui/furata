[CmdletBinding()]
param(
    [ValidateSet('syn','pnr','all')]
    [string]$ProcessName = 'all',
    [string]$GowinRoot = 'E:\Gowin\Gowin_V1.9.12.03_x64'
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'furata.gprj'
$gwSh = Join-Path $GowinRoot 'IDE\bin\gw_sh.exe'
if (!(Test-Path -LiteralPath $project)) { throw "Project not found: $project" }
if (!(Test-Path -LiteralPath $gwSh)) { throw "gw_sh.exe not found: $gwSh" }

$tcl = Join-Path $env:TEMP 'furata_gowin_run.tcl'
@(
    "open_project $($project -replace '\\','/')"
    'set_option -top_module acg720_top'
    "run $ProcessName"
    'exit'
) | Set-Content -LiteralPath $tcl -Encoding ASCII

Get-Content -LiteralPath $tcl | & $gwSh 2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Gowin $ProcessName completed. Top module: acg720_top"
