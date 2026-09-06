<#
.SYNOPSIS
  Odstranitev storitve in firewall pravila. PODATKI OSTANEJO (mapa data se ne ise).
  Ponovna namestitev z install-windows.ps1 torej vsebuje igralce, prijave in dnevnike.
#>
[CmdletBinding()]
param(
  [string]$InstallDir = 'C:\CodeX\site',
  [string]$TaskName = 'CodeX-Site',
  [int]$Port = 3000,
  [switch]$RemoveData
)
$ErrorActionPreference = 'Stop'

$data = Join-Path $InstallDir 'data'
$stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$safety = Join-Path (Split-Path -Parent $InstallDir) "codex-podatki-PRED-ODSTRANITVIJO-$stamp"

if (Test-Path $data) {
  Write-Host "==> varnostna kopija podatkov -> $safety" -ForegroundColor Cyan
  Copy-Item -Path $data -Destination $safety -Recurse -Force
}

Write-Host '==> ustavljam procese' -ForegroundColor Cyan
Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*server.js*' } | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force
}

foreach ($t in @($TaskName, "$TaskName-Watchdog")) {
  if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $t -Confirm:$false
    Write-Host "    storitev '$t' odstranjena" -ForegroundColor Green
  }
}

$rule = 'CodeX Community (stran)'
if (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue) {
  Remove-NetFirewallRule -DisplayName $rule
  Write-Host "    firewall pravilo odstranjeno" -ForegroundColor Green
}

if ($RemoveData) {
  Write-Host "==> IZBRIŠEM tudi podatke v $data (kopija je na $safety)" -ForegroundColor Yellow
  Remove-Item -Recurse -Force $data -ErrorAction SilentlyContinue
} else {
  Write-Host "    mapa $data je ostala - tam so igralci, prijavnice, whitelist in dnevniki" -ForegroundColor Green
}
Write-Host 'gotovo. Ce zelis odstraniti se kodo: Remove-Item -Recurse -Force ' $InstallDir
