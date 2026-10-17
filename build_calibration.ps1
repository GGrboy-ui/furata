[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$OssCadSuite='G:\iverilog',
    [string]$GowinRoot='E:\Gowin\Gowin_V1.9.12.03_x64'
)
$ErrorActionPreference='Stop'
$calRepo=$PSScriptRoot
if(!$OutputDirectory){$OutputDirectory=Join-Path $calRepo ('build\motor_calibration_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}
$calOutput=[IO.Path]::GetFullPath($OutputDirectory)
$calProject=Join-Path $calOutput 'project'
if(Test-Path -LiteralPath $calProject){throw "Release project already exists: $calProject"}
if($calOutput.TrimEnd('\') -eq $calRepo.TrimEnd('\')){throw 'Output must be a separate release directory'}
New-Item -ItemType Directory -Force -Path $calOutput | Out-Null

# Exclude the embedded identifier from its own digest. Hash the relative names
# and source bytes, including constraints and project inputs, in stable order.
$calInputs=@(Get-ChildItem -LiteralPath (Join-Path $calRepo 'src') -File -Recurse | Sort-Object FullName)
$calInputs+=Get-Item -LiteralPath (Join-Path $calRepo 'furata.gprj')
$calProcess=Join-Path $calRepo 'impl\furata_process_config.json'
if(Test-Path -LiteralPath $calProcess){$calInputs+=Get-Item -LiteralPath $calProcess}
$calDigestStream=[IO.MemoryStream]::new()
$calUtf8=[Text.UTF8Encoding]::new($false)
foreach($calInput in $calInputs){
    $calRelative=$calInput.FullName.Substring($calRepo.Length+1).Replace('\','/')
    $calContent=[IO.File]::ReadAllText($calInput.FullName)
    if($calRelative -eq 'src/board/acg720_top.v'){
        $calContent=[regex]::Replace($calContent,"CALIBRATION_BUILD_ID=32'h[0-9A-Fa-f]{8}","CALIBRATION_BUILD_ID=32'h00000000")
    }
    $calBytes=$calUtf8.GetBytes($calRelative+[char]0+$calContent+[char]0)
    $calDigestStream.Write($calBytes,0,$calBytes.Length)
}
$calSha=[Security.Cryptography.SHA256]::Create()
$calSourceHash=([BitConverter]::ToString($calSha.ComputeHash($calDigestStream.ToArray()))).Replace('-','').ToLowerInvariant()
$calSha.Dispose(); $calDigestStream.Dispose()
$calBuildId=$calSourceHash.Substring(0,8).ToUpperInvariant()
$calTop=Join-Path $calRepo 'src\board\acg720_top.v'
$calTopText=[IO.File]::ReadAllText($calTop)
$calTopText=[regex]::Replace($calTopText,"CALIBRATION_BUILD_ID=32'h[0-9A-Fa-f]{8}",("CALIBRATION_BUILD_ID=32'h"+$calBuildId))
[IO.File]::WriteAllText($calTop,$calTopText,$calUtf8)

New-Item -ItemType Directory -Path $calProject | Out-Null
foreach($calDirectory in @('src','sim','web','doc')){
    Copy-Item -LiteralPath (Join-Path $calRepo $calDirectory) -Destination (Join-Path $calProject $calDirectory) -Recurse
}
foreach($calFile in @('furata.gprj','run_gowin.ps1','README.md','build_calibration.ps1')){
    Copy-Item -LiteralPath (Join-Path $calRepo $calFile) -Destination $calProject
}
if(Test-Path -LiteralPath $calProcess){
    New-Item -ItemType Directory -Force -Path (Join-Path $calProject 'impl') | Out-Null
    Copy-Item -LiteralPath $calProcess -Destination (Join-Path $calProject 'impl\furata_process_config.json')
}
$calPrevious=Join-Path $calRepo 'impl\pnr\furata.fs'
if(Test-Path -LiteralPath $calPrevious){Copy-Item -LiteralPath $calPrevious -Destination (Join-Path $calOutput 'furata.previous.fs')}

$calCoreText=[IO.File]::ReadAllText((Join-Path $calRepo 'src\rtl\control_core.v'))
$calParams=@{}
foreach($calName in @('CLK_HZ','PWM_HZ','COUNTS_PER_REV','CENTER','BALANCE_BOOST_RANGE_TENTHS','BALANCE_BOOST_MAX_PERCENT')){
    $calMatch=[regex]::Match($calTopText,('\b'+$calName+'=([0-9_]+)'))
    if($calMatch.Success){$calParams[$calName]=[int]($calMatch.Groups[1].Value.Replace('_',''))}
}
foreach($calName in @('ANGLE_KP','ANGLE_KI','ANGLE_KD','POSITION_KP','POSITION_KI','POSITION_KD')){
    $calMatch=[regex]::Match($calCoreText,('\b'+$calName+'=([0-9_]+)'))
    if($calMatch.Success){$calParams[$calName]=[int]($calMatch.Groups[1].Value.Replace('_',''))}
}
$calParams['PWM_MAX']=[int]($calParams['CLK_HZ']/$calParams['PWM_HZ'])
$calManifest=[ordered]@{
    schemaVersion=1; protocol='DZCAL1'; buildId=$calBuildId
    sourceSha256=$calSourceHash; bitstreamSha256=$null
    createdAt=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time').ToString('o')
    parameters=$calParams; bitstreamPath=(Join-Path $calOutput 'furata.calibration.fs')
    validation='pending'; hardwareMeasured=$false
}
function Save-CalManifest {
    $calJson=$calManifest | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $calOutput 'calibration-manifest.json'),$calJson,$calUtf8)
    [IO.File]::WriteAllText((Join-Path $calRepo 'web\calibration-manifest.json'),$calJson,$calUtf8)
    [IO.File]::WriteAllText((Join-Path $calProject 'web\calibration-manifest.json'),$calJson,$calUtf8)
}
Save-CalManifest
Push-Location -LiteralPath $calProject
try {
    & .\sim\run_oss.ps1 -OssCadSuite $OssCadSuite -SkipLint
    if($LASTEXITCODE -ne 0){throw 'RTL regression failed'}
    & node --check web/app.js; if($LASTEXITCODE -ne 0){throw 'Web syntax check failed'}
    foreach($calTest in @('test-core.cjs','test-app.cjs','test-calibration-core.cjs','test-calibration-app.cjs','test-calibration-serial.cjs')){
        & node (Join-Path 'web' $calTest)
        if($LASTEXITCODE -ne 0){throw "Web test failed: $calTest"}
    }
    & node sim/check_web_telemetry.js --local
    if($LASTEXITCODE -ne 0){throw 'Telemetry compatibility check failed'}
    & .\run_gowin.ps1 -GowinRoot $GowinRoot
    $calTimingPath=Join-Path $calProject 'impl\pnr\furata_tr_content.html'
    $calTiming=[Net.WebUtility]::HtmlDecode([regex]::Replace([IO.File]::ReadAllText($calTimingPath),'<[^>]+>',' '))
    $calTiming=[regex]::Replace($calTiming,'\s+',' ')
    $calFmax=[regex]::Match($calTiming,'clk\s+[0-9.]+\(MHz\)\s+([0-9.]+)\(MHz\)')
    $calTns=[regex]::Match($calTiming,'clk\s+Setup\s+(-?[0-9.]+)\s+(\d+)\s+clk\s+Hold\s+(-?[0-9.]+)\s+(\d+)')
    if(!$calFmax.Success -or !$calTns.Success){throw 'Cannot verify the Gowin timing summary'}
    $calTimingMetrics=@{
        fmaxMHz=[double]$calFmax.Groups[1].Value
        setupViolations=[int]$calTns.Groups[2].Value
        holdViolations=[int]$calTns.Groups[4].Value
    }
    if($calTimingMetrics.fmaxMHz -lt ($calParams.CLK_HZ/1000000) -or
       $calTimingMetrics.setupViolations -ne 0 -or $calTimingMetrics.holdViolations -ne 0){
        throw 'Gowin timing did not meet the configured clock; this bitstream is not a release'
    }
    $calManifest['timing']=$calTimingMetrics
    $calBitstream=Join-Path $calProject 'impl\pnr\furata.fs'
    Copy-Item -LiteralPath $calBitstream -Destination $calManifest.bitstreamPath
    $calManifest.bitstreamSha256=(Get-FileHash -LiteralPath $calBitstream -Algorithm SHA256).Hash.ToLowerInvariant()
    $calManifest.validation='software checks and Gowin implementation completed; hardware unmeasured'
    Save-CalManifest
} finally {Pop-Location}
Write-Output "Calibration release: $calOutput"
Write-Output "Build ID: $calBuildId"
