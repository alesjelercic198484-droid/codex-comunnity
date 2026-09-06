<#
.SYNOPSIS
  Preklopi mapo, ki je bila namescena iz ZIP-a, na git, da lahko kasneje posodabljas
  z enim ukazom (.\scripts\update-windows.ps1). PODATKI in config.json ostanejo pri miru.

.EXAMPLE
  .\scripts\enable-git-updates.ps1                       # uporati mapo, kde je skript
  .\scripts\enable-git-updates.ps1 -InstallDir C:\CodeX\site -Branch main
#>
[CmdletBinding()]
param(
  [string]$InstallDir = '',
  [string]$Branch = 'arena/01a0756b-codex-comunnity',
  [string]$RepoUrl = 'https://github.com/alesjelercic198484-droid/codex-comunnity.git',
  [string]$TaskName = 'CodeX-Site'
)
$ErrorActionPreference = 'Stop'
if (-not $InstallDir) { $InstallDir = Split-Path -Parent $PSScriptRoot }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Write-Host 'Git ni namesten: winget install Git.Git  (ali https://git-scm.com/download/win), nato znova.' -ForegroundColor Red
  exit 1
}
if (-not (Test-Path (Join-Path $InstallDir 'server.js'))) { throw "v $InstallDir ni server.js - napacna mapa" }

Push-Location $InstallDir
try {
  if (Test-Path '.git') { Write-Host 'mapa je ze git repozitorij'; exit 0 }

  Write-Host '==> varnostna kopija podatkov in nastavitev' -ForegroundColor Cyan
  $stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
  $keep = Join-Path $env:TEMP "codex-pre-git-$stamp"
  New-Item -ItemType Directory -Force -Path $keep | Out-Null
  foreach ($d in @('data', 'config.json')) {
    if (Test-Path $d) { Copy-Item -Path $d -Destination $keep -Recurse -Force; Write-Host "    shranjeno: $d" }
  }

  Write-Host '==> inicializiram git in povlecem kodo' -ForegroundColor Cyan
  git init -q
  git remote add origin $RepoUrl
  git fetch --quiet origin $Branch
  # odpusti lokalne spremembe, a NE idi preko podatkov (so gitignored)
  git checkout -f -q -B $Branch "origin/$Branch"
  git reset -q --hard "origin/$Branch"

  Write-Host '==> preverjam, da je vse na svojem mestu' -ForegroundColor Cyan
  foreach ($d in @('server.js', 'config.example.json', 'scripts\install-windows.ps1')) {
    if (-not (Test-Path $d)) { throw "manjka $d po preklopu na git" }
  }
  if (-not (Test-Path 'config.json') -and (Test-Path (Join-Path $keep 'config.json'))) {
    Copy-Item -Path (Join-Path $keep 'config.json') -Destination . -Force
    Write-Host '    config.json obnovljen' -ForegroundColor Green
  }

  Write-Host ''
  Write-Host "GOTIVO. Od zdaj naprej: .\scripts\update-windows.ps1 -Branch '$Branch'" -ForegroundColor Green
  Write-Host "  (kopija pred preklopom: $keep)" -ForegroundColor DarkGray
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "  ponovni zagon: Restart-ScheduledTask -TaskName $TaskName" -ForegroundColor DarkGray
  }
} finally {
  Pop-Location
}
