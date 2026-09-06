<#
.SYNOPSIS
  Rocni zagon v ozadju za testiranje na VPS-u ali lokalno (brez Task Schedulerja).
  Ustavi se z: .\scripts\run.ps1 -Stop
#>
[CmdletBinding()]
param(
  [int]$Port = 0,
  [switch]$Stop
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot

if ($Stop) {
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*server.js*' } | ForEach-Object {
    Write-Host "ustavljam pid $($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force
  }
  exit 0
}

if ($Port -gt 0) { $env:PORT = "$Port" }
Write-Host "zaganjam: node server.js  (mapa: $here)" -ForegroundColor Cyan
Write-Host 'Ustavitev: Ctrl+C' -ForegroundColor DarkGray
Push-Location $here
try { & node server.js } finally { Pop-Location }
