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
    # M18 drives onboard 74HC595 DS and must be available as user IO.
    'set_option -use_sspi_as_gpio 1'
    "run $ProcessName"
    'exit'
) | Set-Content -LiteralPath $tcl -Encoding ASCII

$started = Get-Date
$buildDir = Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
$logPath = Join-Path $buildDir "gowin_$ProcessName.log"
$messages = @(Get-Content -LiteralPath $tcl | & $gwSh 2>&1 | Tee-Object -FilePath $logPath)
$toolExitCode = $LASTEXITCODE
if ($toolExitCode -ne 0) { throw "Gowin exited with code $toolExitCode. See $logPath" }
# gw_sh can return zero after a failed run; never accept its old bitstream.
if ($messages | Where-Object { "$_" -match '^\s*ERROR\b' }) {
    throw "Gowin reported an error. See $logPath"
}
if ($ProcessName -ne 'syn') {
    $bitstreamPath = Join-Path $PSScriptRoot 'impl/pnr/furata.fs'
    if (!(Test-Path -LiteralPath $bitstreamPath) -or
        (Get-Item -LiteralPath $bitstreamPath).LastWriteTime -lt $started) {
        throw "Gowin did not produce a fresh bitstream: $bitstreamPath"
    }
}
Write-Host "Gowin $ProcessName completed. Top module: acg720_top"
