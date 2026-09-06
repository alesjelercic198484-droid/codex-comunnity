<#
.SYNOPSIS
  Posodobitev kode iz GitHub + ponovni zagon. Podatki v data/ se NE dotaknejo.
  Vedno najprej naredi varnostno kopijo podatkov.
#>
[CmdletBinding()]
param(
  [string]$InstallDir = 'C:\CodeX\site',
  [string]$TaskName = 'CodeX-Site',
  [string]$Branch = '',
  [int]$Port = 3000
)
$ErrorActionPreference = 'Stop'
$repo = $InstallDir

Write-Host "==> 1/4  Varnostna kopija podatkov" -ForegroundColor Cyan
$stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$data = Join-Path $repo 'data'
$backupTo = Join-Path (Split-Path -Parent $repo) "codex-podatki-$stamp"
if (Test-Path $data) {
  Copy-Item -Path $data -Destination $backupTo -Recurse -Force
  Write-Host "    shranjeno: $backupTo" -ForegroundColor Green
} else {
  Write-Host "    (mapa $data ne obstaja - nic za kopirat)" -ForegroundColor Yellow
}

Write-Host "==> 2/4  Posodabljam kodo" -ForegroundColor Cyan
Push-Location $repo
try {
  if (-not (Test-Path '.git')) { throw 'ta mapa ni git repozitorij - popravi InstallDir ali uporabi install-windows.ps1' }
  git fetch origin --prune
  if ($Branch) { git checkout $Branch }
  git reset --hard '@{u}'
  Write-Host '    koda posodobljena' -ForegroundColor Green
} finally { Pop-Location }

Write-Host "==> 3/4  Ponovni zagon storitve" -ForegroundColor Cyan
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
  Restart-ScheduledTask -TaskName $TaskName
  Start-Sleep -Seconds 4
} else {
  Write-Host "    storitev '$TaskName' ne obstaja - zazeni ročno: node server.js" -ForegroundColor Yellow
}

Write-Host "==> 4/4  Preizkus delovanja" -ForegroundColor Cyan
for ($i = 0; $i -lt 15; $i++) {
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 3
    if ($r.StatusCode -eq 200) {
      Write-Host "    stran tece: $($r.Content -replace '\s+',' ')" -ForegroundColor Green
      exit 0
    }
  } catch { Start-Sleep -Seconds 2 }
}
Write-Host "    STRAN NE ODGOVARJA na 127.0.0.1:$Port - vrni kodo ali preveri dnevnik:" -ForegroundColor Red
Write-Host "    Get-Content '$data\logs\events.jsonl' -Tail 30" -ForegroundColor Yellow
exit 1
