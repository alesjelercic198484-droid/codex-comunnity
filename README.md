# CodeX Community — stran + whitelist sistem

Spletna stran FiveM skupnosti z **javno prijavnico**, **admin ploščo**, **whitelist** in
**dnevnikom (logom) vseh dogodkov**. Vsi podatki se hranijo **lokalno na tvojem VPS-u** —
nič ne gre na tretje strani (brez Supabase, brez Firebase, brez CDN).

Tehnična izba je namenoma preprosta: **čisti Node.js brez zunanjih odvisnosti** (`npm install`
ni potreben) in **JSON datoteke v `data/`**. Namestitev na Windows Server 2022 je zato
vprašanje minut, hrbtena pa je preprosta: kopija mape.

```
brskalnik ──HTTP──> Node (server.js + src/)  ──>  data/
                        │                          ├─ players.json        (igralci)
                        ├─ logs/events.jsonl        ├─ applications.json   (prijavnice)
                        │                           ├─ whitelist.json      (whitelist)
                        └─ fivem-whitelist.json      ├─ users.json          (osebje, geslo: scrypt)
                             └──> bere FiveM strežnik └─ backups/<datum>/     (samodejne kopije)
```

## Kaj vsebuje

| Področje | Vsebina |
|---|---|
| Javno | Domov, **Prijava na WL** (obrazec), **Status prijave** (po kodi), Pravila, `GET /api/health` |
| Prijavnica | ime, ingame ime, Discord, Steam ID, FiveM license, starost, opis; validacija, honeypot, omejitev prijav na IP/dan, CSRF zaščita |
| Admin plošča | seznam prijav, **Sprejmi / Zavrne / Zahtevaj dodatno**, baza igralcev (dodaj / uredi / izbriši), whitelist, dnevnik, izvozi, nastavitve, osebje z vlogami |
| Whitelist | ob odobritvi se identifier samodejno zapiše v `data/fivem-whitelist.json` (poleg `.txt` in `.array.json`) in po želji skopira na pot FiveM strežnika |
| API | `GET /api/whitelist/check?token=…&license=…` za igrino skripto, `GET /api/whitelist` (cel seznam), `POST /api/whitelist/touch` (dnevnik vstopov) |
| Dnevnik (logi) | vsak dogodek (oddaja prijave, odločitev, sprememba WHITELIST, prijava/odjava osebja, napake) s časom, akterjem in IP; filtri, iskanje, izvoz `.txt` / `.jsonl`, rotacija, samodejno čiščenje po `logs.retentionDays` |
| Varnost | gesla **scrypt**, sejni piškotki `HttpOnly SameSite=Lax` (+ `Secure` nad HTTPS), CSRF ( seja in double-submit), preverjanje vlog, omejitev poskusov prijave, varnostni glave (CSP, `X-Frame-Options: DENY`), izogibanje HTML (zaščita pred XSS), blokada `..` pri statiki, `data/` v `.gitignore` |
| Kopije | stisnjene (`gzip`) samodejne kopije v `data/backups/<datum>/` + gumb v admin plošči + `scripts/backup-windows.ps1` |

## 1. Namestitev na Windows Server 2022 (VPS)

Povzetek; korak za korakom (tudi HTTPS, IIS, Caddy, selitev) je v
[docs/DEPLOY-WINDOWS-SERVER-2022.md](docs/DEPLOY-WINDOWS-SERVER-2022.md).

```powershell
# 1) RDP na VPS, odpri PowerShell KOT SKRBNIK
# 2) en skript naredi vse: Node, git clone, config.json, samodejni zagon, firewall, test
git clone https://github.com/alesjelercic198484-droid/codex-comunnity.git C:\CodeX\site
cd C:\CodeX\site
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1 -WithWatchdog \
  -Branch 'arena/01a0756b-codex-comunnity'     # izpusti, ce je koda ze zdruzena v main
```

Skript na koncu **izpiše začetno geslo** za `http://IP-VPS-a:3000/admin`
(prijavi se, stran takoj zahteva nastavitev lastnega gesla, nato **izbriši `data\ADMIN-START.txt`**).

Že nameščeno? `powershell -NoProfile -File .\scripts\update-windows.ps1` — najprej kopira
podatke, nato `git reset --hard` na najnovejšo različico, ponovni zagon in test delovanja.

### Linux (enaka koda, če boš selil)

```bash
git clone <ta repozitorij> /opt/codex-site && cd /opt/codex-site
node server.js                     # ali systemd / nginx: docs/DEPLOY-WINDOWS-SERVER-2022.md#linux
```

## 2. Lokalni zagon (za preizkus)

```bash
node server.js            # ali npm start   -> http://localhost:3000
npm run dev               # samodejni ponovni zagon ob spremembi datotek
npm test                  # 18 preizkusov: prijave, whitelist, dnevnik, varnost
npm run selfcheck         # obisk vseh strani in vseh akcij v čistem okolju
npm run seed              # vzorčni igralci in prijave za ogled admin plošče
```

Prvi zagon brez `config.json` teče na privzetih vrednostih, geslo skrbnika se generira v
`data/ADMIN-START.txt`.

Če hočeš videti, kako je videti prava namestitev, si oglej namestitveni skript in
dnevniške primere: `scripts/install-windows.ps1`, `docs/API.md`. Za hiter ogled z
vzorčnimi podatki:

```bash
npm run seed && npm start     # nato http://localhost:3000/admin  (geslo v data/ADMIN-START.txt)
```

## 3. Nastavitve (`config.json`)

`config.json` je **v `.gitignore`** — sme obstajati samo na VPS-u. Nastavitve iz
`data/settings.json` (urejaš v admin plošči) preglasita config.json za: ime strani, podnaslov,
Discord povabilo, connect naslov, odprte/zaprte prijave, mejo starosti in API token.

```json
{
  "port": 3000,
  "host": "0.0.0.0",
  "publicUrl": "https://tvoj-domena.si",
  "admin": { "username": "admin", "password": "" },
  "applications": { "open": true, "minAge": 16, "maxPerIpPerDay": 5 },
  "whitelist": { "exportFile": "fivem-whitelist.json", "copyTo": [] },
  "api": { "enabled": true, "token": "" },
  "logs": { "retentionDays": 90 },
  "backup": { "enabled": true, "everyHours": 6, "keepDays": 14 }
}
```

Okoljske spremenljivke imajo prednost pred `config.json`: `PORT`, `HOST`, `PUBLIC_URL`,
`DATA_DIR`, `ADMIN_USER`, `ADMIN_PASSWORD`, `API_TOKEN`, `APPS_OPEN`, `TRUST_PROXY`,
`SECURE_COOKIES`, `CSRF_SECRET`, `CONFIG_PATH`.

**Zaradi HTTPS:** če je stran za reverse proxy-jem (IIS + ARR, Caddy, nginx), nastavi
`publicUrl` na `https://…` in `trustProxy: true`, sicer brskalnik zavrne varne piškotke
in prijava v admin ploščo ne deluje.

## 4. Whitelist v FiveM

Tri načini — izberi enega (vsi se osvežijo ob vsaki odločitvi v admin plošči):

1. **Datoteka**: `data/fivem-whitelist.json` (objekti), `fivem-whitelist.txt` (po en
   identifier na vrstico) in `fivem-whitelist.array.json`. Za samodejno kopiranje na mapo
   strežnika nastavi `config.whitelist.copyTo` na npr.
   `["C:/FiveM/server/config/whitelist.json"]` (uporabi `/`, ne `\`).
2. **API preverjanje** (priporočeno): `GET /api/whitelist/check?token=TOKEN&license=steam:110000112345678`
   → `{ "allowed": true, "expires": null }`. Primer skripte in opomba za `server.cfg`:
   [docs/API.md](docs/API.md).
3. **Ročni izvoz**: gumb *Zapiši / osveži izvoz* ali `GET /admin/whitelist/export.json`.

Token nastane v **Admin → Nastavitve → Ustvari API token**.

## 5. Podatki, kopije, brisanje (GDPR)

* Vse je v mapi `data/` (če jo premakneš, nastavi `dataDir`). Selitev = kopiraj mapo.
* **Nikoli ne objavi `data/` ali `config.json` na GitHub.** V `.gitignore` sta, a pred
  `git add -A` vseeno preveri `git status`.
* Igralec prosi za izbris podatkov → Admin → Prijavnice → *Izbriši prijavnico*; igralec in
  whitelist uredi posebej (Admin → Igralci / Whitelist). Vsak izbris je zabeležen v
  dnevniku s podatkom, kdo je izbrisal.
* Dnevniki: `data/logs/events.jsonl` (rotacija pri 8 MB, hrani 6 datotek), samodejno
  čiščenje po `logs.retentionDays`, ročno čiščenje v Admin → Dnevnik.
* Kopije: `data/backups/<datum>/*.json.gz` vsakih `backup.everyHours` ur (hrani
  `backup.keepDays` dni) in ob vsakem normalnem ustavljanju. Zunanjo kopijo naredi
  `scripts/backup-windows.ps1 -Zip` in jo shrani izven VPS-a.

## 6. Kaj se je spremenilo glede na staro `index.html`

Stara datoteka je bila nedokončena predloga (naslov, štiri gumbi in vgrajen Readdy AI
pripomoček gradnika strani). Odstranjena je; če jo potrebuješ, je v zgodovini:
`git show 88e4189:index.html`. Nova različica:

* slovenščina, jasna struktura (Domov / Prijava / Status / Pravila);
* nobenih zunanjih virov (ne Google Fonts, ne `cdnjs`, ne Readdy) → hitrejše nalaganje in
  stran deluje tudi, kadar nimaš interneta ali ko CDN odpove;
* prava funkcionalnost: prijava se shrani, ekipa jo obdela, whitelist se zapiše, vse je v
  dnevniku;
* `meta description`, `robots`, `security.txt`, dostopnost (skip link, semantične oznake,
  slog za tiskanje) in mobilni prikaz.

## 7. Struktura

```
server.js                zagon
config.example.json      vzorec nastavitev (kopiraj v config.json)
src/app.js               router, seje, CSRF, varnostne glave, vzdrževalni ciklusi
src/config.js            config.json + okoljske spremenljivke
src/store.js             zbirke v JSON (atomic write, obnova iz kopije)
src/logs.js              dnevnik dogodkov (JSONL, rotacija, iskanje)
src/auth.js              scrypt gesla, seje, osebje, omejevanje poskusov
src/whitelist.js         whitelist + izvoz v FiveM oblike
src/validate.js          validacija prijav, igralcev in osebja
src/http.js              piškotki, telesa zahtev, statika, varnostne glave
src/services.js          združevanje nastavitev, statistika, podatki o sistemu
src/routes/*.js          javne / admin / API poti
src/views/*.js           HTML predloge (samodejno izogibanje)
public/                  CSS, JS, favicon (streženi pod /assets/)
scripts/                 Windows: namestitev, posodobitev, kopije, varuh, zagon
test/app.test.js         preizkusi celotnega toka
```

## 8. Omejitve, da veš

* Ni obvestila po e-pošti ob odobritvi — igralec status preveri s kodo (SMTP je mogoče dodati).
* Ni Discord OAuth — Discord se preveri ročno (vnos + podeljevanje vloge ostane tvoja naloga).
* Shramba je datotečna (JSON). Za ~50.000+ zapisov razmisli o SQLite/Postgres; za velikost
  FiveM skupnosti zadošča (vse je indeksirano in v spominu).
* Zaščita pred DDoS ni del te kode — to reši Cloudflare ali IIS/Caddy na samem VPS-u.
