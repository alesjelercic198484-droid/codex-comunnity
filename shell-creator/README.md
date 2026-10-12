# Shell Creator - FiveM (qb-core)

In-game Shell Creator za FiveM qb-core. Ustvarjaj custom interiere v igri!

## ✨ Funkcionalnosti
- In-Game Editor za prop placement
- 70+ propov (furniture, kitchen, bathroom, lighting, etc.)
- 32 barv za stene/tla
- Multi-floor (do 5 nadstropij)
- Teleporter sistem
- MySQL shranjevanje
- Housing export (ps-housing, qs-housing, nolag, esx_property, loaf-housing)

## 📋 Zahteve
- qb-core
- oxmysql

## 🚀 Namestitev
1. Kopiraj `shell-creator` v `resources/`
2. V `server.cfg` dodaj: `ensure shell-creator`
3. Nastavi ACE permissions:
```
add_ace group.admin shellcreator.admin allow
```

## 🎮 Komande
- `/shellcreator` - Odpri UI menu
- `/shelltp [id]` - Teleport do shell-a
- `/shelllist` - Prikaži shelle

## 🎹 Kontrole (v Editorju)
| Tipka | Akcija |
|-------|--------|
| Arrows | Premakni prop |
| PgUp/PgDn | Gor/dol |
| Q/E | Rotiraj |
| Shift | Hitrejše |
| G | Grid Snap |
| Enter | Postavi/Izberi |
| X | Prekliči |
| Del | Izbriši |
| Ins | Podvoji |
| F5 | Shrani |
| F6 | Menu |
| Backspace | Zapri editor |

## 📝 Konfiguracija
Odpri `config.lua` za nastavitve (sloti, propi, barve, permissions).
