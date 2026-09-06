# API za FiveM (in druge skripte)

Vključi se z `config.api.enabled: true` in žetonom `config.api.token`
(ustvari se v **Admin → Nastavitve → Ustvari API token**). Brez nastavljenega žetona
zaščiteni konci vrnejo `503`, z napačnim žetonom `401`.

Osnovni naslov: `https://tvoj-domena.si` (ali `http://IP-VPS-a:3000`).

## Konci

| Metoda | Pot | Avtentikacija | Opis |
|---|---|---|---|
| `GET` | `/api/health` | ne | stanje strani, število odprtih prijav, število whitelist, napake v 24 h |
| `GET` | `/api/whitelist/check?token=…&license=…` | da | ali sme identifier na strežnik (trenutni odgovor) |
| `GET` | `/api/whitelist?token=…` | da | cel seznam aktivnih zapisov (za sinhronizacijo) |
| `POST` | `/api/whitelist/touch` | da | zabeleži vstop igralca v dnevnik strani: `{ "license": "steam:…", "serverId": 12 }` |

### `GET /api/whitelist/check`

```json
{
  "allowed": true,
  "reason": null,
  "identifier": "steam:110000112345678",
  "name": "Jane_Novak",
  "expires": null,
  "checkedAt": "2026-09-06T07:00:00.000Z"
}
```

Pri `allowed: false` je vedno podan `reason` (`ni na whitelisti`, `odstranjen iz
whiteliste`, `whitelist je potekla`). Identifierji so normalizirani (male črke, brez
presledkov), zato `license:ABC…` in `license:abc…` pomenita isti zapis.

## Primeri

```bash
curl -s "http://127.0.0.1:3000/api/health"

curl -s "http://127.0.0.1:3000/api/whitelist/check?token=$TOKEN&license=steam:110000112345678"

# žeton gre lahko tudi v glavo
curl -s -H "x-api-key: $TOKEN" "http://127.0.0.1:3000/api/whitelist"
```

## FiveM skripta (server, Lua)

Preverjanje ob vstopu, z predpomnjenjem, da API ne drži obremenitve na vsak join:

```lua
-- fxmanifest.lua: server_script 'wl_api.lua'
local TOKEN = GetConvar('codex_wl_token', '')                       -- samo na strežniku, nikoli v GitHub
local BASE  = GetConvar('codex_wl_api', 'http://127.0.0.1:3000/api')
local CACHE = {}                                                    -- [identifier] = { allowed, until, reason }
local CACHE_TTL = 300                                               -- 5 minut

local function allowedFor(identifier, cb)
  local hit = CACHE[identifier]
  if hit and hit.until > os.time() then return cb(hit.allowed, hit) end

  PerformHttpRequest(
    ('%s/whitelist/check?token=%s&license=%s'):format(BASE, TOKEN, identifier),
    function(status, body)
      local allowed, reason = false, 'API ni dosegljiv'
      if status == 200 then
        local data = json.decode(body) or {}
        allowed = data.allowed == true
        reason = data.reason
      elseif status == 401 then
        reason = 'napacen API token'
      end
      CACHE[identifier] = { allowed = allowed, reason = reason, until = os.time() + CACHE_TTL }
      cb(allowed, CACHE[identifier])
    end,
    'GET', '', { ['User-Agent'] = 'codex-whitelist/1.0' }
  )
end

AddEventHandler('playerJoining', function()
  local source = ...
  local id = GetPlayerIdentifierBySource and GetPlayerIdentifierBySource(source, 1)
    or GetPlayerLicense(source)
  if not id then return end

  allowedFor(id, function(allowed, info)
    if allowed then
      TriggerClientEvent('chat:addMessage', source, { 'CodeX: dobrodošel na strežniku.' })
    else
      CancelEvent()
      DropPlayer(source, ('CodeX: nisi na whitelisti (%s). Oddaj prijavo: %s/status'):format(
        info.reason or 'preveri status', GetConvar('codex_site', 'https://tvoj-domena.si')))
    end
  end)
end)

-- ročna osvežitev predpomnilnika, kadar skrbnik spremeni whitelist
RegisterNetEvent('codex:wl:refresh', function(identifier)
  if identifier then CACHE[identifier] = nil else CACHE = {} end
end)
```

Opombe:

* `license` je lahko kateri koli FiveM identifier (`license:…`, `license2:…`, `steam:…`,
  `xbl:…`, `discord:…`). V bazi je shranjen tisti, ki ga je igralec navedel v prijavi; če
  tvoj framework preverja `license2`, dodaj ločen zapis v **Admin → Whitelist**.
* API je brez stanja — klicati ga je mogoče z več lokacij hkrati (npr. main + dev strežnik).
* Ce je VPS za Cloudflare, omeji pot `/api/*` (Access policy) in uporabi `HTTPS`, da žeton
  ne potuje v navadnem besedilu.

## Datotečni način (brez API klicev)

Če raje bereš JSON z diska: `config.whitelist.copyTo` naj kaže na mapo FiveM strežnika,
npr.

```json
"whitelist": {
  "exportFile": "fivem-whitelist.json",
  "copyTo": ["C:/FiveM/server/config/codex-whitelist.json"]
}
```

Ob vsaki odločitvi (sprejmem / zavrnem / dodam / odstranim) se datoteka prepiše, zato
ponovni zagon FiveM strežnika ni potreben — razen če tvoja skripta bere datoteko samo ob
zagonu. Takrat ji dodaj branje vsako minuto:

```lua
local WL
local function readWhitelist(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local data = json.decode(f:read('*a')) or {}
  f:close()
  local set = {}
  for _, row in ipairs(data.whitelist or data) do set[row.identifier] = row end
  return set
end

CreateThread(function()
  while true do
    WL = readWhitelist(GetResourcePath(GetCurrentResourceName()) .. '/codex-whitelist.json') or WL
    wait(60000)
  end
end)
```

## Preveri pred uporabo

```powershell
# na VPS-u (ali s koder koli, ki sme dostopati do strani)
Invoke-RestMethod "http://127.0.0.1:3000/api/health"
Invoke-RestMethod "http://127.0.0.1:3000/api/whitelist/check?token=<TOKEN>&license=steam:110000112345678"
```

`allowed` mora biti `true` za identifier, ki je v Admin → Whitelist, in `false` za tujega.
