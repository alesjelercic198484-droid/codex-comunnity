<#
.SYNOPSIS
  Namestitev CodeX Community strani na Windows Server 2022 (VPS).

.DESCRIPTION
  Skript naredi vse, kar je potrebno za zagon:
    1. namesti Node.js LTS (ce ga ni) in Git (ce ga ni) prek winget
    2. prekine/zagotovi, da je mapa projekta na C:\CodeX\site (git clone ali copy)
    3. ustvari config.json (lokalno, NIKOLI na GitHub) z varnim API tokenom
    4. registrira samodejni zagon ob zagonu Windows (Task Scheduler, brez prijave)
    5. odpre Windows Firewalls za pravilni port
    6. zažene storitev, počaka na /api/health in izpiše začetno geslo za admin ploščo

  Ponovni zagon skripta je varen (posodobi kodo in nastavitve, podatkov v data/ ne briše).

.EXAMPLE
  # kot skrbnik (desni klik -> Run with PowerShell, ali pooblaščen PowerShell):
  .\scripts\install-windows.ps1

.EXAMPLE
  .\scripts\install-windows.ps1 -Port 8080 -RepoUrl "https://github.com/alesjelercic198484-droid/codex-comunnity.git" -Branch "arena/01a0756b-codex-comunnity" -WithWatchdog
#>
[CmdletBinding()]
param(
  [string]$RepoUrl = 'https://github.com/alesjelercic198484-droid/codex-comunnity.git',
  [string]$Branch = 'main',
  [string]$InstallDir = 'C:\CodeX\site',
  [int]$Port = 3000,
  [string]$PublicUrl = '',
  [string]$TaskName = 'CodeX-Site',
  [string]$DataDir = '',
  [switch]$WithWatchdog,
  [switch]$SkipNode,
  [switch]$UseCurrentUser
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$startTime = Get-Date

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    [!] $msg" -ForegroundColor Yellow }

# --- 0. skrbniške pravice ---------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Warn2 'Poganjaš brez skrbniških pravic - namestitev sistema (storitev, firewall) bo morda uspela samo delno.'
  Write-Warn2 'Priporočeno: odpri PowerShell kot Administrator in zaženi skript znova.'
}

# --- 1. Node.js in Git ------------------------------------------------------
function Find-Node {
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($p in @("$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe")) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

if (-not $SkipNode) {
  Write-Step 'Preverjam Node.js'
  $node = Find-Node
  if ($node) {
    Write-Ok "Node $(& $node -v) je nameščen: $node"
  } else {
    Write-Warn2 'Node.js ni nameščen - poskušam ga namestiti prek winget'
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
      Write-Warn2 'winget ni na voljo. Namesti Node.js LTS ročno: https://nodejs.org/ (x64 .msi, "Add to PATH"), nato zaženi skript znova.'
      throw 'Node.js manjka in ga ni mogoče samodejno namestiti.'
    }
    & winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $node = Find-Node
    if (-not $node) { throw 'Node.js je bil namescen, a ga ne najdem v PATH-om. Odprl novo konzolo in poskusi znova.' }
    Write-Ok "Node namescen: $node"
  }
} else {
  $node = Find-Node
  if (-not $node) { throw 'SkipNode je nastavljen, a Node.js ni nameščen.' }
}

$git = Get-Command git -ErrorAction SilentlyContinue

# --- 2. koda projekta ------------------------------------------------------
# Ce je bil projekt razsirjen iz ZIP-a (mapa brez .git, a s server.js) in ciljna mapa
# ne obstaja, namescimo kar na tem mestu - ni potrebe po git clone.
$fromZip = $false
if (-not $PSBoundParameters.ContainsKey('InstallDir') `
    -and -not (Test-Path (Join-Path $InstallDir 'server.js')) `
    -and (Test-Path (Join-Path $root 'server.js'))) {
  Write-Warn2 "ciljna mapa $InstallDir ne obstaja, skript pa tece iz mape s kodo - namestim kar tukaj ($root)."
  $InstallDir = $root
  $fromZip = $true
}

Write-Step "Koda projekta v $InstallDir"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $InstallDir) | Out-Null
if (Test-Path (Join-Path $InstallDir '.git')) {
  if ($git) {
    Push-Location $InstallDir
    & git fetch origin
    if ($Branch) { & git checkout $Branch 2>&1 | Out-Null }
    & git pull --ff-only origin $Branch
    Pop-Location
    Write-Ok 'Koda posodobljena z git pull'
  } else {
    Write-Warn2 'Git manjka - koda ostane kot je (za posodobitev namesti Git).'
  }
} elseif (Test-Path (Join-Path $InstallDir 'server.js')) {
  if ($fromZip) {
    Write-Ok 'koda je ze tukaj (razsirjeno iz ZIP-a) - git clone ni potreben'
    Write-Warn2 'za posodobitve z enim ukazom preklopi na git: .\scripts\enable-git-updates.ps1'
  } else {
    Write-Ok 'Mapa je ze zapolnjena (brez .git) - preskakujem clone.'
  }
} elseif ($git) {
  & git clone --depth 1 $RepoUrl $InstallDir
  if ($Branch) { Push-Location $InstallDir; & git checkout $Branch; Pop-Location }
  Write-Ok 'Koda preklonana iz GitHub'
} else {
  Write-Warn2 'Git manjka - kopiram trenutno mapo projekta v ciljno mapo.'
  Copy-Item -Path (Join-Path $root '*') -Destination $InstallDir -Recurse -Force
  Write-Ok "Kopirano v $InstallDir"
}

$server = Join-Path $InstallDir 'server.js'
if (-not (Test-Path $server)) {
  Write-Host ''
  Write-Host "    V $InstallDir ni datoteke server.js - izbrana veja '$Branch' se zdi prazna (tam je samo stara predloga index.html)." -ForegroundColor Red
  if ($git) {
    Write-Host '    Razpolozljive veje na GitHubu:' -ForegroundColor Yellow
    Push-Location $InstallDir; git branch -r 2>&1 | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }; Pop-Location
    Write-Host "    Ponovi z ustrezno vejo, npr.:" -ForegroundColor Yellow
    Write-Host "      .\scripts\install-windows.ps1 -Branch 'arena/01a0756b-codex-comunnity'" -ForegroundColor White
  }
  throw 'namestitev ustavljena: koda aplikacije ni na najdeni veji.'
}

# --- 3. config.json --------------------------------------------------------
Write-Step 'Nastavitve (config.json)'
$example = Join-Path $InstallDir 'config.example.json'
$conf = Join-Path $InstallDir 'config.json'
$token = [Convert]::ToBase64String((1..24 | ForEach-Object { Get-Random -Maximum 256 }) | ForEach-Object { [byte]$_ }) -replace '[+/=]', ''
if (-not $token -or $token.Length -lt 20) { $token = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') }

if (Test-Path $conf) {
  $existing = Get-Content $conf -Raw | ConvertFrom-Json
  $existing.port = $Port
  if ($PublicUrl) { $existing.publicUrl = $PublicUrl }
  if ($DataDir) { $existing.dataDir = $DataDir }
  if (-not $existing.api.token) { $existing.api.token = $token }
  $existing | ConvertTo-Json -Depth 10 | Set-Content -Path $conf -Encoding UTF8
  Write-Ok 'obstoječi config.json ohranjen (posobljen samo port / javni naslov)'
} else {
  $cfg = Get-Content $example -Raw | ConvertFrom-Json
  $cfg.port = $Port
  $cfg.host = '0.0.0.0'
  $cfg.publicUrl = $PublicUrl
  $cfg.api.token = $token
  if ($DataDir) { $cfg.dataDir = $DataDir }
  $cfg | ConvertTo-Json -Depth 10 | Set-Content -Path $conf -Encoding UTF8
  Write-Ok "config.json ustvarjen (API token generiran - za FiveM: $token)"
}

# podatki naj bodo izven spletne mape, ce jih streze IIS
$dataPath = if ($DataDir) { $DataDir } else { Join-Path $InstallDir 'data' }
New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $dataPath 'logs') | Out-Null

# --- 4. samodejni zagon (Task Scheduler) ----------------------------------
Write-Step 'Registracija storitve (zagon ob zagonu Windows)'
$action = New-ScheduledTaskAction -Execute $node -Argument 'server.js' -WorkingDirectory $InstallDir
$triggerBoot = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -StartWhenAvailable

if ($UseCurrentUser) {
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest
} else {
  $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
}

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
  Write-Warn2 'obstoječa storitev je bila odstranjena in bo na novo registrirana'
}
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggerBoot -Settings $settings -Principal $principal `
  -Description 'CodeX Community - spletna stran in baza (igralci, prijavnice, whitelist, dnevniki)' | Out-Null
Write-Ok "storitev '$TaskName' registrirana (zagon ob zagonu sistema, samodejni poskus x3 ob napaki)"

# --- 5. Firewall ----------------------------------------------------------
Write-Step 'Windows Firewall'
$ruleName = 'CodeX Community (stran)'
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port `
    -Profile Any | Out-Null
  Write-Ok "vrata $Port odprta (vstopno)"
} else {
  Write-Ok "vrata $Port so ze odprta"
}

# --- 6. watchdog (ce je zahtevan) ----------------------------------------
if ($WithWatchdog) {
  Write-Step 'Watchdog (vsakih 5 minut preveri, ali stran živi)'
  $watch = Join-Path $PSScriptRoot 'watchdog.ps1'
  $wAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watch`" -Port $Port -TaskName $TaskName" -WorkingDirectory $PSScriptRoot
  $wTrigger = New-ScheduledTaskTrigger -Recurring -RepetitionInterval (New-TimeSpan -Minutes 5) -At (Get-Date).AddMinutes(1)
  $wTask = "$TaskName-Watchdog"
  if (Get-ScheduledTask -TaskName $wTask -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $wTask -Confirm:$false }
  Register-ScheduledTask -TaskName $wTask -Action $wAction -Trigger $wTrigger -Principal $principal `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden) | Out-Null
  Write-Ok "watchdog storitev '$wTask' registrirana"
}

# --- 7. zagon in preverjanje --------------------------------------------
Write-Step 'Zagon in preverjanje'
Start-ScheduledTask -TaskName $TaskName
$ok = $false
for ($i = 0; $i -lt 25; $i++) {
  Start-Sleep -Seconds 2
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 4
    if ($resp.StatusCode -eq 200) { $ok = $true; break }
  } catch { Start-Sleep -Seconds 1 }
}

if ($ok) {
  Write-Ok 'STRAN TECE'
  Write-Host ''
  Write-Host '    Odgovor preizkusa delovanja:' -ForegroundColor DarkGray
  Write-Host ('    ' + ($resp.Content -replace '\s+', ' ')) -ForegroundColor DarkGray
} else {
  Write-Warn2 'Preizkus delovanja ni odgovoril v 50 s. Preveri dnevnik:'
  Write-Host "    Get-Content '$dataPath\logs\events.jsonl' -Tail 20" -ForegroundColor Yellow
  Write-Host "    Schtasks /Query /TN $TaskName /V /FO LIST" -ForegroundColor Yellow
}

# --- 8. admin dostop ------------------------------------------------------
$startFile = Join-Path $dataPath 'ADMIN-START.txt'
Write-Step 'Admin plošča'
Write-Host "    Naslov:      http://<IP-VPS-a>:$Port/admin" -ForegroundColor White
if (Test-Path $startFile) {
  Write-Host '    Začetni dostop (izpišite ga, nato datoteko IZBRIŠITE):' -ForegroundColor Yellow
  Get-Content $startFile | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
  Write-Warn2 'Ko se prijaviš in geslo spremeniš: Remove-Item "' + $startFile + '"'
} else {
  Write-Warn2 "Če je to posodobitev, obstoječe geslo velja. Pozabljeno geslo: izbriši $dataPath\sessions.json in nastavi novo geslo z:"
  Write-Host "    node `"$InstallDir\scripts\hash-password.mjs`" TvojeNovoGeslo123" -ForegroundColor Gray
}

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host " CodeX Community - namestitev končana ($([int]((Get-Date) - $startTime).TotalSeconds) s)" -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host "  Mapa projekta : $InstallDir"
Write-Host "  Podatki (VPS) : $dataPath   <- TO redno kopiraj (varnostna kopija)"
Write-Host "  Dnevniki      : $dataPath\logs\events.jsonl"
Write-Host "  Izzvoz WHITELIST : $dataPath\fivem-whitelist.json"
Write-Host "  Port / zaganjanje: $Port  (storitev: $TaskName)"
Write-Host ''
Write-Host '  Ukazi za vsakdanjo rabo:'
Write-Host "    Restart-ScheduledTask -TaskName $TaskName      # ponovni zagon"
Write-Host "    Get-ScheduledTaskInfo -TaskName $TaskName      # kdaj je bil zadnji zagon / napaka"
Write-Host "    .\scripts\update-windows.ps1                    # posodobitev iz GitHub (git pull + restart)"
Write-Host "    .\scripts\backup-windows.ps1                    # rocna varnostna kopija podatkov"
Write-Host ''
Write-Host '  HTTPS (priporočeno): namesti IIS + URL Rewrite/ARR ali Caddy in obrni'
Write-Host "  na port $Port - navodila so v docs\DEPLOY-WINDOWS-SERVER-2022.md" -ForegroundColor Gray
