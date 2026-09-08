# OQV2 QUESTS — Unlimited Mission System

**Origen Quest V2 inspired · ESX · ox_lib · ox_inventory · ox_target · oxmysql**

> Author: **Codex Dev: #Alesh48 5654**
> *Made with CodeX Dev.*

A complete, database-backed quest framework for FiveM with a premium dark NUI that lets
administrators build **missions, locations, NPC givers and hostile "Evil NPC" groups**
entirely in-game — no file editing, no restarts.

---

## Table of contents

1. [Features](#features)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Permissions — who can open the panel](#permissions--who-can-open-the-panel)
5. [Commands & keybinds](#commands--keybinds)
6. [Using the admin panel](#using-the-admin-panel)
7. [Configuration](#configuration)
8. [Database](#database)
9. [Exports](#exports)
10. [Events](#events)
11. [Localisation](#localisation)
12. [Project layout](#project-layout)
13. [Testing & tooling](#testing--tooling)
14. [Troubleshooting](#troubleshooting)
15. [Credits](#credits)

---

## Features

The resource is built as **8 self-contained modules** (one per workstream):

| # | Module | What it does |
|---|--------|--------------|
| 1 | **Core & Framework bridge** | ESX bootstrap, identifiers, money, inventory bridge, notifications, rate limiting, ACE/group permissions |
| 2 | **Database layer** | oxmysql schema creation + migrations, CRUD for every entity, progress, discovery, audit logs, leaderboard |
| 3 | **Schema & validation** | Normalises and validates every mission/location/NPC, coerces types, detects circular prerequisite chains |
| 4 | **Progression** | XP curve, levels, level-up rewards, per-mission progress, rolling cooldown windows, discovery tracking |
| 5 | **Missions runtime** | 8 objective types, server-side distance/item/money validation, restrictions, schedules, reward payout |
| 6 | **Evil NPC system** | Hostile groups with companions, weapons, difficulty, proximity spawning, loot tables, police dispatch |
| 7 | **Admin NUI** | 8-page dark panel: dashboard, missions, locations, hostiles, quest tree, players, logs, settings |
| 8 | **Player experience** | Journal (`/quests`), discovered-locations map, live objective tracker HUD, XP/level-up toasts |

**Highlights**

- **Unlimited content** — everything lives in MySQL and is created through the UI.
- **Visual quest tree** — chain missions so mission 2 stays locked until mission 1 is done; circular chains are rejected before they can be saved.
- **8 objective types** — `give_item`, `collect`, `deliver`, `goto`, `kill`, `interact`, `pay`, `wait`.
- **Restrictions** — everyone, civilians only, a job, a gang, a business, or a minimum level.
- **Repeatability** — one-shot, hourly, daily, weekly, monthly, custom or infinite, with an optional *N runs per window* limit.
- **Time windows** — a mission can be offered only between e.g. 22:00 and 05:00 (wrap-around supported).
- **NPC or object givers** — pick a ped model or a prop, with animations, scenarios, dialogue and rotating spawn points.
- **Player alerts** — per-mission title, description, duration and sound.
- **Server-authoritative** — every turn-in, kill report and loot pickup is distance- and inventory-checked on the server, plus a per-player event rate limiter.
- **Import / export** — back up or move your whole dataset as JSON from the panel.
- **Multi-language** — English and Spanish shipped, one JSON file per language.
- **Offline-safe UI** — no CDN fonts or icon packs; all 24 icons are inline SVG.

---

## Requirements

| Dependency | Notes |
|------------|-------|
| [es_extended](https://github.com/esx-framework/esx_core) | ESX Legacy (1.9+) |
| [ox_lib](https://github.com/overextended/ox_lib) | Callbacks, notifications, context menus, progress bars, dialogs |
| [ox_inventory](https://github.com/overextended/ox_inventory) | Item checks, removal, granting, carry-weight validation |
| [ox_target](https://github.com/overextended/ox_target) | Interaction with mission givers and hostile corpses |
| [oxmysql](https://github.com/overextended/oxmysql) | Persistence |

Server artifacts: **6683 or newer** (Lua 5.4 + `fxv2_oal` are enabled in the manifest).

---

## Installation

1. **Drop the folder** into your resources directory:

   ```
   resources/[custom]/oqv2_quests
   ```

2. **Import the SQL** (optional — the resource creates its tables automatically on first start,
   but importing is faster and lets you review the schema):

   ```bash
   mysql -u root -p your_database < oqv2_quests/sql/oqv2_quests.sql
   ```

3. **Add it to `server.cfg`**, *after* its dependencies:

   ```cfg
   ensure oxmysql
   ensure ox_lib
   ensure ox_inventory
   ensure ox_target
   ensure es_extended

   ensure oqv2_quests

   # give your admin group access to the panel
   add_ace group.admin oqv2.admin allow
   ```

4. **Add the reward/objective items** used by the shipped examples to `ox_inventory/data/items.lua`
   (or edit the examples in `config/missions.lua`):

   ```lua
   ['scrapmetal']    = { label = 'Scrap Metal',    weight = 800,  stack = true, close = true },
   ['sealed_package']= { label = 'Sealed Package', weight = 1200, stack = true, close = true },
   ['evidence_bag']  = { label = 'Evidence Bag',   weight = 500,  stack = true, close = true },
   ```

   The example rewards and hostile loot also use `water`, `bandage` and `weapon_ammo`,
   which ship with ox_inventory by default.

5. **Restart the server** and run `/oqv2` in-game as an admin.

On the first boot the resource creates its tables and seeds the four example missions,
four locations and two hostile groups from `config/*.lua`
(set `Config.SeedFromConfig = false` to skip seeding once you have your own content).

---

## Permissions — who can open the panel

`/oqv2` is **admin-only**. A player is granted access if **any** of these match
(`config/config.lua` → `Config.Admin`):

| Method | Setting | Example |
|--------|---------|---------|
| ESX group | `groups` | `{ 'admin', 'superadmin', 'owner', 'god' }` |
| FiveM ACE | `ace` | `add_ace group.admin oqv2.admin allow` in `server.cfg` |
| Hard-coded identifier | `identifiers` | `'license:0000…'`, `'steam:110000…'`, `'discord:123…'` |
| Server console | `allowConsole` | server id `0` |

Denied attempts are notified to the player, printed to the console (`logDenied`) and written to
`oqv2_logs`. **Every** admin callback re-checks the permission server-side — the client never
decides who is an admin.

---

## Commands & keybinds

| Command | Side | Who | Description |
|---------|------|-----|-------------|
| `/oqv2` | server | **admins** | Opens the admin panel NUI |
| `oqv2 reload` | console | console | Reloads all data from the database |
| `oqv2 stats` | console | console | Prints a content/progress summary |
| `/oqv2xp <id> <amount>` | server | admins + console | Grants XP to a player |
| `/quests` | client | everyone | Opens the player journal (missions, map, progress) |
| `F7` | client | everyone | Journal keybind — remappable, or `Config.Journal.keybind = false` |
| `/oqv2abandon` | client | everyone | Abandons the active mission (with confirmation) |

---

## Using the admin panel

Open `/oqv2`. The sidebar has 8 pages:

1. **Dashboard** — live counts, online players, completions, active runs, database status, recent activity.
2. **Missions** — create/edit/duplicate/enable/delete. The editor has 7 tabs:
   *General · Objectives · Requirements · Rewards · Access · Progression · Alert*.
3. **Locations** — the mission givers. 6 tabs:
   *General · Entity · Positions · Interaction · Map & Time · Missions*.
   Use **Use my coords** / **Pick on map** / **Teleport** to place points without leaving the game.
4. **Hostiles** — the Evil NPC groups. 4 tabs: *General · Combat · Spawn · Loot*.
5. **Quest tree** — a tier-by-tier view of your prerequisite chains; broken or circular links are shown before you save.
6. **Players** — everyone online: level, XP, active mission, completions. Grant XP, set a level, cancel a mission or reset progress.
7. **Logs** — the audit trail of every admin action and player completion.
8. **Settings** — read-only view of the runtime configuration, plus **Export**, **Import** and **Reload**.

**Typical workflow (matching the Origen v2 flow):**

```
Missions → New
  ├─ General ....... name, description, icon, category
  ├─ Objectives .... e.g. "give_item scrapmetal x10"
  ├─ Requirements .. required level, items, money
  ├─ Rewards ....... cash / bank / dirty money / items / XP
  ├─ Access ........ everyone | civilians | job | gang | business | level
  ├─ Progression ... prerequisites + repeatability (daily, weekly, …)
  └─ Alert ......... on-screen title, description, duration, sound
Locations → New
  ├─ Entity ........ ped or object model, animation/scenario
  ├─ Positions ..... one or more spawn points (rotated between)
  ├─ Map & Time .... blip, discovery radius, active hours
  └─ Missions ...... link the mission(s) offered here
Quest tree → confirm mission 2 is locked behind mission 1
```

Changes are validated, written to MySQL and pushed to every connected client instantly —
no restart, no `refresh`.

---

## Configuration

Everything lives in `config/config.lua`.

| Table | Key settings |
|-------|--------------|
| *(root)* | `Debug`, `Locale` (`en`/`es`), `Framework`, `UseDatabase`, `SeedFromConfig` |
| `Config.Admin` | `command` (default `oqv2`), `groups`, `ace`, `identifiers`, `allowConsole`, `logDenied` |
| `Config.Journal` | `enabled`, `command` (`quests`), `keybind` (`F7`) |
| `Config.UI` | `brand`, `subtitle`, `author`, `footer`, `accent`, `accentAlt`, `sounds`, `blurBackdrop` |
| `Config.Progression` | `maxLevel` (100), `baseXP` (500), `curve` (1.09), `levelRewards` |
| `Config.Interaction` | `targetDistance`, `spawnDistance`, `despawnDistance`, tick rates, `useBlips`, `discoveryRadius` |
| `Config.Economy` | `moneyAccount`, `checkCarry`, `logTransactions` |
| `Config.EvilNPC` | `maxActiveGroups`, `defaultRespawn`, `dispatchExport`, `policeAlertChance`, `lootRadius`, `corpseCleanup` |
| `Config.Notify` | Single function — replace its body to use your own notification resource |
| `Config.Security` | `maxDistanceToLocation` (12.0), `rateLimitMs` (750), `kickOnAbuse`, `abuseThreshold` |
| `Config.CooldownPresets` | Seconds behind `hourly` / `daily` / `weekly` / `monthly` |

**XP curve:** `XP(level) = baseXP * curve^(level-1)`.
With the defaults, level 2 costs 500 XP, level 10 ≈ 1 000, level 50 ≈ 33 000 and reaching
level 100 takes roughly 28 million total XP.

**Custom notifications** — swap ox_lib for anything:

```lua
Config.Notify = function(src, data)
    if IsDuplicityVersion() then
        TriggerClientEvent('my_notify:show', src, data.title, data.description, data.type)
    else
        exports['my_notify']:show(data.title, data.description, data.type)
    end
end
```

**Police dispatch** — point it at your dispatch resource:

```lua
Config.EvilNPC.dispatchExport = { resource = 'cd_dispatch', method = 'CustomAlert' }
```

---

## Database

Seven InnoDB tables, all prefixed `oqv2_`:

| Table | Contents |
|-------|----------|
| `oqv2_missions` | Mission definitions (`uid`, `name`, `enabled`, JSON `data`) |
| `oqv2_locations` | Mission givers |
| `oqv2_npcs` | Hostile groups |
| `oqv2_players` | Per-identifier XP, level, completion count |
| `oqv2_progress` | Per-mission state, completions, cooldown window |
| `oqv2_discovered` | Which locations a player has found |
| `oqv2_logs` | Audit trail |

Missing columns are added automatically at boot, so upgrading never requires a manual `ALTER`.
Setting `Config.UseDatabase = false` runs the whole resource from `config/*.lua` in memory —
useful for testing, but nothing is persisted.

---

## Exports

**Server**

```lua
exports.oqv2_quests:getPlayerLevel(source)              --> number
exports.oqv2_quests:getPlayerXP(source)                 --> number (total)
exports.oqv2_quests:addPlayerXP(source, amount)         --> boolean
exports.oqv2_quests:hasCompletedMission(source, uid)    --> boolean
exports.oqv2_quests:startMission(source, uid)           --> boolean, message
exports.oqv2_quests:getMissions()                       --> table
exports.oqv2_quests:getLocations()                      --> table
exports.oqv2_quests:reload()                            --> reloads from the database
```

**Client**

```lua
exports.oqv2_quests:isNuiOpen()          --> boolean
exports.oqv2_quests:getActiveMission()   --> table|nil
exports.oqv2_quests:getPlayerLevel()     --> number
exports.oqv2_quests:openJournal()
exports.oqv2_quests:closeUI()
```

---

## Events

Client-side listeners you can hook for your own scripts:

```lua
RegisterNetEvent('oqv2:client:missionCompleted', function(mission, rewards) end)
RegisterNetEvent('oqv2:client:levelUp',          function(level) end)
RegisterNetEvent('oqv2:client:xp',               function(data) end)   -- { gained, level, xp, need, percent, total }
RegisterNetEvent('oqv2:client:discovered',       function(uid, name) end)
RegisterNetEvent('oqv2:client:missionsUnlocked', function(missions) end)
```

---

## Localisation

Add `locales/<code>.json`, copy the keys from `en.json`, then set `Config.Locale = '<code>'`.
Strings support `{placeholders}`:

```json
{ "mission_cooldown": "Available again in {time}." }
```

English (`en`) and Spanish (`es`) are included.

---

## Project layout

```
oqv2_quests/
├── fxmanifest.lua
├── README.md
├── config/
│   ├── config.lua          settings & branding
│   ├── missions.lua        4 example missions
│   ├── locations.lua       4 example givers
│   └── npcs.lua            2 example hostile groups
├── shared/
│   ├── utils.lua           helpers, locale, XP maths
│   └── schema.lua          normalisation + validation + cycle detection
├── server/
│   ├── sv_database.lua     oxmysql layer & migrations
│   ├── sv_core.lua         ESX bridge, permissions, registry
│   ├── sv_progression.lua  XP, levels, cooldown windows, discovery
│   ├── sv_missions.lua     mission runtime & rewards
│   ├── sv_npcs.lua         hostile groups & loot
│   ├── sv_admin.lua        admin callbacks (snapshot/save/delete/…)
│   └── sv_commands.lua     /oqv2, /oqv2xp, exports
├── client/
│   ├── cl_core.lua         state, sync, helpers
│   ├── cl_locations.lua    streaming, peds/objects, blips, ox_target
│   ├── cl_missions.lua     objectives, markers, progress bars
│   ├── cl_npcs.lua         hostile spawning, combat, looting
│   ├── cl_tracker.lua      objective HUD
│   ├── cl_nui.lua          NUI bridge
│   ├── cl_editor.lua       coord picking, model preview, teleport
│   └── cl_commands.lua     /quests, keybind, exports
├── locales/
│   ├── en.json
│   └── es.json
├── sql/
│   └── oqv2_quests.sql
└── web/
    ├── index.html
    └── assets/
        ├── css/style.css
        └── js/  (app, admin, editors, journal, hud, icons, core)
```

---

## Testing & tooling

This build ships only after passing three automated suites:

| Suite | Coverage | Result |
|-------|----------|--------|
| Lua syntax lint | all 22 `.lua` files | **0 errors** |
| Lua runtime suite | utils, XP curve, schema, validation, cycle detection, config integrity, boot, permissions, mission lifecycle, cooldowns, restrictions, schedules, hostile NPCs, loot, admin CRUD, import/export, rate limiter | **70 / 70 passing** |
| NUI suite | all 8 admin pages, every editor tab, list add/remove, chip toggles, draft commit, journal, HUD, 24 icons | **64 / 64 passing** |

A cross-file static analyzer also verifies that every `OQ.*` call is defined, every net event has a
handler, every ox_lib callback awaited is registered, and every `O.post()` from the UI has a
matching `RegisterNUICallback`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `/oqv2` says you have no permission | Add `add_ace group.admin oqv2.admin allow` to `server.cfg`, or put your ESX group in `Config.Admin.groups`, or add your license to `Config.Admin.identifiers` |
| Panel opens empty | The database isn't reachable — check the oxmysql connection string and the console for `Failed to create a table` |
| Nothing spawns in the world | The location is disabled, has no spawn points, or its **Active hours** window excludes the current in-game time |
| Rewards are not delivered | The item name doesn't exist in `ox_inventory/data/items.lua`, or the player is overweight (`Config.Economy.checkCarry`) |
| "You are too far away." on turn-in | Raise `Config.Security.maxDistanceToLocation`, or move the location's spawn point closer to the objective |
| Mission never becomes available again | Its repeat mode is *one-shot*; change it on the **Progression** tab |
| A mission can't be saved | Read the red validation list — the most common causes are an empty name, no objectives, or a circular prerequisite chain |

Set `Config.Debug = true` for verbose console output.

---

## Credits

**Codex Dev: #Alesh48 5654**
*Made with CodeX Dev.*

Design inspired by Origen Quest V2. Built for ESX with ox_lib, ox_inventory, ox_target and oxmysql.
