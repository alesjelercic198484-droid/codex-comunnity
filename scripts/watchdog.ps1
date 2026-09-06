<#
.SYNOPSIS
  Varuh (watchdog): ce stran ne odgovarja, zažene storitev znova.
  Namenjen Task Schedulerju (npr. vsakih 5 minut). Sam ne ukine nic.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\watchdog.ps1 -Port 3000 -TaskName CodeX-Site
#>
[CmdletBinding()]
param(
  [int]$Port = 3000,
  [string]$TaskName = 'CodeX-Site',
  [string]$LogFile = '',
  [string]$InstallDir = 'C:\CodeX\site'
)

$ErrorActionPreference = 'SilentlyContinue'
if (-not $LogFile) {
  $LogFile = Join-Path $InstallDir 'data\watchdog.log'
  if (-not (Test-Path (Split-Path -Parent $LogFile))) {
    $LogFile = Join-Path $env:TEMP 'codex-watchdog.log'
  }
}

function Log($msg) {
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
  # ohrani dnevnik majhen
  if ((Get-Item $LogFile).Length -gt 1MB) {
    Get-Content $LogFile -Tail 400 | Set-Content $LogFile -Encoding UTF8
  }
}

function Test-Health {
  try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 5
    return ($r.StatusCode -eq 200)
  } catch {
    return $false
  }
}

if (Test-Health) { exit 0 }

Log 'stran ne odgovarja - poskusam zagnati storitev'
$task = Get-ScheduledTask -TaskName $TaskName
if (-not $task) {
  Log "storitev '$TaskName' ne obstaja - ce ni namesceno, zazeni: .\scripts\install-windows.ps1"
  exit 1
}

if ($task.State -eq 'Running') {
  # tece, a ne odgovarja -> zadnji proces se je zataknil: ustopi ga in znova zazeni
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*server.js*' } | ForEach-Object {
    Log "ustavljam zataknjen proces node pid $($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force
  }
  Start-Sleep -Seconds 3
}

Start-ScheduledTask -TaskName $TaskName
for ($i = 0; $i -lt 10; $i++) {
  Start-Sleep -Seconds 3
  if (Test-Health) { Log 'po zagonu stran spet tece'; exit 0 }
}
Log 'zagon ni uspel - preveri Get-Content data\logs\events.jsonl -Tail 30'
exit 1
