<#
.SYNOPSIS
  Varnostna kopija podatkov (igralci, prijavnice, whitelist, dnevniki) na izbrano mesto.
  Aplikacija samea dela kopije v data\backups - ta skript je za zunajnjo kopijo
  (npr. na drug disk ali omrežno mapo), kar je edino res varno, ce VPS crkne.

.EXAMPLE
  .\scripts\backup-windows.ps1
  .\scripts\backup-windows.ps1 -To 'D:\varnostne-kopije' -Zip
#>
[CmdletBinding()]
param(
  [string]$InstallDir = 'C:\CodeX\site',
  [string]$To = '',
  [switch]$Zip,
  [switch]$IncludeLogs
)
$ErrorActionPreference = 'Stop'
$data = Join-Path $InstallDir 'data'
if (-not (Test-Path $data)) { throw "ni podatkov v $data" }

$dest = if ($To) { $To } else { Join-Path (Split-Path -Parent $InstallDir) 'varnostne-kopije' }
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$target = Join-Path $dest "codex-podatki-$stamp"

Write-Host "==> kopiram $data -> $target" -ForegroundColor Cyan
$exclude = if ($IncludeLogs) { @() } else { @('logs') }
New-Item -ItemType Directory -Force -Path $target | Out-Null
Get-ChildItem -Path $data -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
  if ($_.PSIsContainer) {
    Copy-Item -Path $_.FullName -Destination (Join-Path $target $_.Name) -Recurse -Force
  } else {
    Copy-Item -Path $_.FullName -Destination $target -Force
  }
}

if ($Zip) {
  $zipPath = "$target.zip"
  Compress-Archive -Path (Join-Path $target '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force
  Remove-Item -Recurse -Force $target
  $target = $zipPath
  Write-Host "==> stisnjeno: $zipPath" -ForegroundColor Green
}

$size = (Get-ChildItem -Recurse -Force $target | Measure-Object -Property Length -Sum).Sum
Write-Host ("    koncano: {0}  ({1:N0} kB)" -f $target, ($size / 1KB)) -ForegroundColor Green

# pocisti staro: hrani zadnjih 14 kopij
$all = Get-ChildItem -Path $dest -Filter 'codex-podatki-*' | Sort-Object LastWriteTime -Descending
if ($all.Count -gt 14) {
  $all | Select-Object -Skip 14 | Remove-Item -Recurse -Force
  Write-Host '    stare kopije pociscene (hranim zadnjih 14)' -ForegroundColor DarkGray
}
