[CmdletBinding()]
param([int]$Port = 8766)
$ErrorActionPreference = 'Stop'
# An older checkout may already serve 8766. Never reuse its page silently.
$requestedPort = $Port
while ($true) {
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    try { $probe.Start(); break }
    catch { $Port++; if ($Port -gt $requestedPort + 20) { throw 'No available local web port.' } }
    finally { $probe.Stop() }
}
if ($Port -ne $requestedPort) { Write-Host "Port $requestedPort is occupied; using $Port for this checkout." }
Write-Host "Web directory: $PSScriptRoot"
Write-Host "Position boot / VEL1 monitor: http://localhost:$Port"
Write-Host 'Open this URL in desktop Chrome / Edge. Ctrl+C stops the local server.'
& python -m http.server $Port --bind 127.0.0.1 --directory $PSScriptRoot
