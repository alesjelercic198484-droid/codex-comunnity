# Paste install — qb-inventory (CodeX Roleplay)

Branch: `arena/783f2a94-codex-comunnity`

Vsako datoteko odpri na spodnji povezavi, klikni **Raw** (ali Copy raw file),
in vsebino prilepi v datoteko s točno tako potjo na svojem strežniku.

| # | Pot na strežniku (relativno na mapo resursa) | Raw povezava |
|---|---------------------------------------------|--------------|
| 1 | `fxmanifest.lua` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/fxmanifest.lua](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/fxmanifest.lua) |
| 2 | `config.lua` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/config.lua](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/config.lua) |
| 3 | `client/main.lua` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/client/main.lua](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/client/main.lua) |
| 4 | `client/pedpreview.lua` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/client/pedpreview.lua](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/client/pedpreview.lua) |
| 5 | `server/core.lua` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/server/core.lua](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/server/core.lua) |
| 6 | `server/main.lua` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/server/main.lua](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/server/main.lua) |
| 7 | `html/index.html` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/index.html](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/index.html) |
| 8 | `html/style.css` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/style.css](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/style.css) |
| 9 | `html/app.js` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/app.js](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/app.js) |
| 10 | `html/locales.js` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/locales.js](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/locales.js) |
| 11 | `html/images/README.txt` | [https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/images/README.txt](https://github.com/alesjelercic198484-droid/codex-comunnity/raw/arena/783f2a94-codex-comunnity/qb-inventory/html/images/README.txt) |

Poti so relativne na mapo `qb-inventory/`. Mapa se **mora** imenovati `qb-inventory`.

## Hitrejša pot (če imaš SSH dostop do strežnika)

```bash
cd /pot/do/resources
git clone --depth 1 -b arena/783f2a94-codex-comunnity https://github.com/alesjelercic198484-droid/codex-comunnity.git codex-tmp
mv codex-tmp/qb-inventory ./qb-inventory
rm -rf codex-tmp
```

## server.cfg

```cfg
ensure qb-core
ensure qb-weapons
ensure qb-inventory
```
