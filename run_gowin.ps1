[CmdletBinding()]
param(
    [ValidateSet('syn','pnr','all')]
    [string]$ProcessName = 'all',
    [string]$GowinRoot = 'E:\Gowin\Gowin_V1.9.12.03_x64',
    [switch]$ForceRebuild
)
$ErrorActionPreference = 'Stop'
$scriptFilePath = $PSCommandPath
$project = Join-Path $PSScriptRoot 'furata.gprj'
$gwSh = Join-Path $GowinRoot 'IDE\bin\gw_sh.exe'
if (!(Test-Path -LiteralPath $project)) { throw "Project not found: $project" }
if (!(Test-Path -LiteralPath $gwSh)) { throw "gw_sh.exe not found: $gwSh" }
$buildDir = Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
$receiptPath = Join-Path $buildDir 'gowin_build_cache.json'
$netlistPath = Join-Path $PSScriptRoot 'impl/gwsynthesis/furata.vg'
$bitstreamPath = Join-Path $PSScriptRoot 'impl/pnr/furata.fs'
$timingPath = Join-Path $PSScriptRoot 'impl/pnr/furata_tr_content.html'
$configPath = Join-Path $PSScriptRoot 'impl/furata_process_config.json'
function FileHash([string]$path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
    return 'missing'
}
function SourceFingerprint {
    $items = @($project, $scriptFilePath)
    $items += @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Recurse -File | ForEach-Object FullName)
    # Include enabled external project sources too, if the project uses any.
    # Gowin may write an XML declaration with version="1"; .NET requires 1.0.
    $projectText = (Get-Content -LiteralPath $project -Raw) -replace '^\s*<\?xml[^>]*\?>',''
    [xml]$xml = $projectText
    $items += @($xml.Project.FileList.File | Where-Object { $_.enable -ne '0' } | ForEach-Object {
        [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $_.path))
    })
    $parts = @($items | Sort-Object -Unique | ForEach-Object {
        $identity = $_
        if ($_.StartsWith($PSScriptRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
            $identity = $_.Substring($PSScriptRoot.Length+1) -replace '\\','/'
        }
        "$identity=$(FileHash $_)"
    })
    $parts += "tool=$gwSh,$((Get-Item -LiteralPath $gwSh).Length),$((Get-Item -LiteralPath $gwSh).LastWriteTimeUtc.Ticks)"
    $bytes = [Text.Encoding]::UTF8.GetBytes(($parts -join "`n"))
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','') } finally { $hasher.Dispose() }
}
function CheckTiming {
    if (!(Test-Path -LiteralPath $timingPath)) { throw 'Missing static timing report.' }
    $timing = Get-Content -LiteralPath $timingPath -Raw
    $setup = [regex]::Match($timing, 'Setup Violated Endpoints</td>\s*<td>(\d+)')
    $hold = [regex]::Match($timing, 'Hold Violated Endpoints</td>\s*<td>(\d+)')
    if (!$setup.Success -or !$hold.Success -or $setup.Groups[1].Value -ne '0' -or $hold.Groups[1].Value -ne '0') {
        throw "Static timing failed; do not treat this bitstream as a verified release. See $timingPath"
    }
}
$lock = $null
try {
    # One build per checkout; independent checkouts use different TCL files.
    $lock = [IO.File]::Open((Join-Path $buildDir 'gowin_build.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $fingerprint = SourceFingerprint
    $configHash = FileHash $configPath
    $receipt = $null
    if (Test-Path -LiteralPath $receiptPath) {
        try { $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json } catch { Write-Verbose 'Ignoring invalid build cache.' }
    }
    $same = $receipt -and $receipt.schema -eq 1 -and $receipt.source -eq $fingerprint -and $receipt.config -eq $configHash
    $sameSyn = $same -and $receipt.netlist -eq (FileHash $netlistPath) -and $receipt.netlist -ne 'missing'
    $sameAll = $sameSyn -and $receipt.bitstream -eq (FileHash $bitstreamPath) -and $receipt.bitstream -ne 'missing' -and $receipt.timing -eq (FileHash $timingPath)
    if (!$ForceRebuild -and (($ProcessName -eq 'syn' -and $sameSyn) -or ($ProcessName -ne 'syn' -and $sameAll))) {
        if ($ProcessName -ne 'syn') { CheckTiming }
        Write-Host "Gowin ${ProcessName}: reused verified output (source/config/tool/output hashes unchanged). Use -ForceRebuild to rebuild."
        return
    }
    if ($ProcessName -eq 'pnr' -and !$sameSyn) {
        throw 'No verified synthesis for these inputs. Run -ProcessName syn or all first.'
    }
    $tcl = Join-Path $buildDir ("gowin_run_{0}.tcl" -f [guid]::NewGuid().ToString('N'))
    @(
        "open_project `"$($project -replace '\\','/')`""
        'set_option -top_module acg720_top'
        # M18 drives onboard 74HC595 DS and must be available as user IO.
        'set_option -use_sspi_as_gpio 1'
        "run $ProcessName"
        'exit'
    ) | Set-Content -LiteralPath $tcl -Encoding ASCII
    $logPath = Join-Path $buildDir "gowin_$ProcessName.log"
    if (Test-Path -LiteralPath $logPath) {
        Copy-Item -LiteralPath $logPath -Destination (Join-Path $buildDir ("gowin_{0}_before_{1}.log" -f $ProcessName,[guid]::NewGuid().ToString('N')))
    }
    $started = Get-Date
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $messages = @(Get-Content -LiteralPath $tcl | & $gwSh 2>&1 | Tee-Object -FilePath $logPath)
    $toolExitCode = $LASTEXITCODE
    $watch.Stop()
    if ($toolExitCode -ne 0 -or ($messages | Where-Object { "$_" -match '^\s*ERROR\b' })) {
        throw "Gowin failed (exit $toolExitCode). See $logPath"
    }
    if ((SourceFingerprint) -ne $fingerprint) { throw 'Sources changed during compilation; output will not be cached.' }
    $freshPath = if ($ProcessName -eq 'syn') { $netlistPath } else { $bitstreamPath }
    if (!(Test-Path -LiteralPath $freshPath) -or (Get-Item -LiteralPath $freshPath).LastWriteTime -lt $started) {
        throw "Gowin did not produce fresh output: $freshPath"
    }
    if ($ProcessName -ne 'syn') { CheckTiming }
    $newReceipt = [ordered]@{
        schema=1; source=$fingerprint; config=(FileHash $configPath); netlist=(FileHash $netlistPath)
        bitstream=$(if ($ProcessName -ne 'syn') { FileHash $bitstreamPath } else { 'missing' })
        timing=$(if ($ProcessName -ne 'syn') { FileHash $timingPath } else { 'missing' })
        completedAt=(Get-Date -Format o); process=$ProcessName; elapsedSeconds=$watch.Elapsed.TotalSeconds
    }
    $newReceipt | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    Write-Host ("Gowin {0} completed in {1:N1} s. Top module: acg720_top" -f $ProcessName,$watch.Elapsed.TotalSeconds)
} finally {
    if ($lock) { $lock.Dispose() }
}
