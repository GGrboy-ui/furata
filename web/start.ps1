[CmdletBinding()]
param([int]$Port = 8765)
$ErrorActionPreference = 'Stop'
Write-Host "Angle monitor: http://localhost:$Port"
Write-Host 'Open this URL in desktop Chrome / Edge. Ctrl+C stops the local server.'
& python -m http.server $Port --bind 127.0.0.1 --directory $PSScriptRoot
