# Namestitev na Windows Server 2022 (VPS)

Ta dokument je namenjen ročni namestitvi prek RDP. Predpostavke: VPS ima javno IP,
dostop do Microsoftovega Wingeta ali prenosa datotek, ti pa si skrbnik (Administrator).

**Če ti je všeč en sam ukaz:**

```powershell
git clone https://github.com/alesjelercic198484-droid/codex-comunnity.git C:\CodeX\site
cd C:\CodeX\site
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1 -WithWatchdog -Branch 'arena/01a0756b-codex-comunnity'
```

> **Opomba o veji:** koda je bila narejena na veji `arena/01a0756b-codex-comunnity`.
> Dokler je ne združiš v `main`, namestitev zahteva `-Branch`:
> `... install-windows.ps1 -Branch 'arena/01a0756b-codex-comunnity'`
> (skript ti to pove in našteje razpoložljive veje, če `server.js` ni najden).

Vse spodaj je razčlenjeno, da veš, kaj se dogaja in kaj preveriti, ko kaj ne dela.

---

## 0. Namestitev iz ZIP-a (brez Gita)

Če na VPS-u nočeš imeta Gita ali nimaš dostopa do GitHuba:

1. Razširi ZIP in celotno vsebino mape prekopiraj v `C:\CodeX\site`.
2. Zaženi `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1 -WithWatchdog`
   iz te mape. Skript zazna, da koda že leži tam (mapa brez `.git`) in namestitev naredi
   na tem mestu; `git clone` preskoči.
3. Če boš kasneje hotel posodabljati z enim ukazom, preklopi mapo na git:
   `.\scripts\enable-git-updates.ps1` (varnostno kopira `data/` in `config.json`, nato
   `git init` + `fetch` + `reset`).

## 1. Priprava VPS-a

1. Poveži se prek RDP (mstsc) ali prek ponudnikovega konzolnega omrežja.
2. Omogoči izvajanje skript (če je blokirano):

   ```powershell
   Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force
   ```

3. Namesti Node.js LTS in Git — skript ju poskusi sam prek wingeta; ročno:

   ```powershell
   winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
   winget install Git.Git -e --accept-source-agreements --accept-package-agreements
   node -v      # mora izpisati v20.x ali novejši
   ```

   Brez wingeta: `https://nodejs.org` (LTS, x64 .msi — pusti kljukico *Add to PATH*) in
   `https://git-scm.com/download/win`. Po namestitvi odpri **novo** okno PowerShell.

## 2. Koda in prva namestitev

```powershell
git clone https://github.com/alesjelercic198484-droid/codex-comunnity.git C:\CodeX\site
cd C:\CodeX\site
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1 -WithWatchdog -Branch 'arena/01a0756b-codex-comunnity'
```

`install-windows.ps1` naredi:

| Korak | Kaj nastori |
|---|---|
| 1 | preveri/namesti Node.js |
| 2 | `git clone` ali `git pull` v `C:\CodeX\site` (parameter `-InstallDir`) |
| 3 | ustvari `config.json` iz `config.example.json` + **naključni API token** |
| 4 | registrira storitev `CodeX-Site` v Task Schedulerju: zagon ob zagonu sistema, račun `SYSTEM`, 3 ponovni poskusi ob napaki |
| 5 | odpre vstopno pravilo firewall za `-Port` (privzeto 3000) |
| 6 | (neobvezno) storitev `CodeX-Site-Watchdog`, ki vsakih 5 minut preveri `/api/health` in ob napaki zažene storitev |
| 7 | zažene storitev, počaka na zdrav odziv in izpiše začetno geslo iz `data\ADMIN-START.txt` |

**Ukazi za vsakdanjo rabo**

```powershell
Restart-ScheduledTask -TaskName CodeX-Site
Get-ScheduledTaskInfo -TaskName CodeX-Site          # zadnji zagon in koda napake
Get-Content C:\CodeX\site\data\logs\events.jsonl -Tail 30
.\scripts\run.ps1                                    # rocni zagon v konzoli (za test)
.\scripts\backup-windows.ps1 -Zip                    # zunanja kopija podatkov
.\scripts\update-windows.ps1                         # posodobitev kode (varno)
.\scripts\uninstall-windows.ps1                      # odstrani storitev/firewall (podatki ostanejo)
```

## 3. Prva prijava v admin ploščo

1. Odpri `http://IP-VPS-a:3000/admin`.
2. Uporabnik: `admin`. Geslo: iz konca namestitve ali iz datoteke
   `C:\CodeX\site\data\ADMIN-START.txt`.
3. Stran te takoj sili v nastavitev **lastnega gesla** (vsaj 12 znakov).
4. **Izbriši začetno datoteko:** `Remove-Item C:\CodeX\site\data\ADMIN-START.txt`
5. V **Nastavitve** uredi: ime strani, podnaslov, Discord povabilo, connect naslov;
   po želju *Ustvari API token* za FiveM.

## 4. HTTPS (priporočeno, da piškotki in DOM ne delajo težav)

Node posluša navadni HTTP. HTTPS daj pred njega — ena od treh možnosti:

### A) Caddy (najlažje, samodejni Let's Encrypt)

```powershell
winget install --id CaddyServer.Caddy -e
notepad C:\Caddyfile
```

```
tvoj-domena.si {
    reverse-proxy / /127.0.0.1:3000
    encode gzip
}
```

```powershell
caddy run --config C:\Caddyfile          # test
sc.exe create Caddy binPath= "caddy run --config C:\Caddyfile --install-service" ; sc.exe start Caddy
```

### B) IIS + URL Rewrite + ARR (če IIS že imaš)

1. V Server Managerju dodaj vlogo *IIS* in *Web Server (HTTP Activation)*.
2. Namesti **URL Rewrite** in **ARR 3.0** (web platform installer).
3. V ARR → Server Proxy Framework → *Enable proxy*, izključi *Reverse rewrite head*.
4. V IIS → tvoja stran (port 80/443 z vezavo na domeno in certifikat) dodaj pravilo **Reverse Proxy**:
   `https://tvoj-domena.si/{R:0}` ← vnesi `http://localhost:3000/{R:0}` (inbound rule).
5. V `config.json`: `"publicUrl": "https://tvoj-domena.si"`, `"trustProxy": true`,
   `"secureCookies": "auto"`. Nato ponovni zagon storitve.
6. Mapa `C:\CodeX\site\data` naj **ne** bo v IIS virtualnem imeniku (podatki so zasebni).

### C) Samo notranje omrežje (brez javnega HTTPS)

V `config.json` nastavi `"host": "127.0.0.1"` in promet do strani pelji prek SSH/RDP
tunela ali obstoječega proxyja. Tako nihče zunaj ne vidi admin plošče.

## 5. Selitev / ponovna namestitev

```powershell
# na novem VPS-u
.\scripts\install-windows.ps1 -Port 3000
# ustavi storitev, kopiraj staro mapo data, zaženi
Restart-ScheduledTask -TaskName CodeX-Site
```

Varno: `robocopy D:\stari\codex\site\data C:\CodeX\site\data /MIR /XD backups`
in nato ponovni zagon. Podatki so navadni JSON — lahko jih pregledaš/urediš tudi v
Notepadu (priporočljivo le ob ustavljeni storitvi).

## 6. Preverjanje, ali je vse OK

```powershell
Invoke-WebRequest http://127.0.0.1:3000/api/health | Select-Object -Expand Content
Get-Content C:\CodeX\site\data\players.json          # igralci
Get-Content C:\CodeX\site\data\applications.json     # prijavnice
Get-Content C:\CodeX\site\data\whitelist.json         # whitelist
Get-Content C:\CodeX\site\data\logs\events.jsonl -Tail 10   # dnevnik
```

Zunanja dostopnost: `https://<IP>:3000/admin` iz brskalnika doma (ne s strežnika).
Če ne odpre — preveri pravilo firewalla in varnostno skupino ponudnika (npr. Security
group v Azure/Oracle/Contabo panelu).

## 7. Pogoste težave

| Težava | Rešitev |
|---|---|
| `Pristop zavrnjen` ob zagonu skripta | odpri PowerShell **kot skrbnik** |
| `node` ni prepoznan | odpri novo konzolo po namestitvi Node; preveri `Get-Command node` |
| Storitev teče, stran ne odgovarja | `Get-Content data\logs\events.jsonl -Tail 30`; v `config.json` je morda pokvarjen JSON (pozor: `C:\` v JSON uporabi `C:/`) |
| Port je že zaseden (`EADDRINUSE`) | `Get-NetTCPConnection -LocalPort 3000`, ali zazeni z `-Port 8080` |
| Prijava v admin ne uspe (piškotek) | nad HTTPS mora biti `publicUrl` z `https://` in `trustProxy: true` |
| Po `update-windows.ps1` stran ne dela | `git reset --hard origin/main`, `Restart-ScheduledTask`, preveri `data/config.json` |
| Antivirus blokira zapisovanje `data\*.json` | dodaj izjemo za mapo `C:\CodeX\site\data` (aplikacija ima vgrajene ponovitve zapisov) |

## 8. Redno vzdrževanje

* **Kopije:** enkrat tedensko zunaj VPS-a — `.\scripts\backup-windows.ps1 -Zip` in datoteko
  shrani v oblaku/omrežni disk. (Aplikacija dela interne kopije vsakih 6 ur sama.)
* **Posodobitve:** `.\scripts\update-windows.ps1` (hrani `data/`, zato je varno).
* **Prostor na disku:** `data\logs` raste do 8 MB × 7 datotek; ohrani `logs.retentionDays`.
* **Gesla:** enkrat na 3 mesece zamenjaj gesla osebja in API token (Nastavitve → *Zamenjaj API token*).
* **Windows Update:** po posodobitvi preveri `Get-ScheduledTaskInfo -TaskName CodeX-Site` —
  storitev se zažene sama ob zagonu.

## Linux (`#linux`)

```bash
sudo mkdir -p /opt/codex-site && sudo git clone <repo> /opt/codex-site
cd /opt/codex-site && node server.js         # za preizkus
sudo cp config.example.json config.json      # uredi port, publicUrl, trustProxy
```

`/etc/systemd/system/codex-site.service`:

```ini
[Unit]
Description=CodeX Community site
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/codex-site
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
Environment=PORT=3000
Environment=TRUST_PROXY=true

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now codex-site
sudo ufw allow 3000/tcp
```
