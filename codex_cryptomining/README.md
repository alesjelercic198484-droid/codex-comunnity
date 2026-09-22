# codex_cryptomining

An advanced, server-authoritative **ESX** crypto mining economy for FiveM: buy warehouses, fill them with real mining rig props, upgrade and maintain them, pay the electricity, watch a live Bitcoin market, and get robbed by other players.

Built with **props and interiors** (base game IPLs out of the box, MLO-ready), no external paid dependency, and a full automated test suite (**361 tests**).

---

## Features

### Warehouses
- 5 pre-configured warehouses (3 small / 2 large), unlimited more via config.
- Bought and sold through a real estate broker NPC.
- Configurable ownership limit per player.
- **Key sharing**: give the keys to other players, revoke them any time.
- Each warehouse runs in its **own routing bucket** so several owners can use the same base game interior without seeing each other.
- Live production, power draw, and wallet statistics.

## About the props and interiors (important)

**This resource contains no 3D models and no MLO.** Nothing is streamed — there is no `stream/` folder.

Instead it *uses* props and interiors that already ship with GTA V, spawning them at runtime with `CreateObjectNoOffset`:

| Role | Base game model |
|---|---|
| Rig chassis | `hei_prop_mini_sever_01` (small server rack) |
| Broken rig | `hei_prop_mini_sever_broken` |
| GPU (stacked per GPU) | `ex_office_swag_electronic` |
| Cooler | `gr_prop_bunker_deskfan_01a` |
| Terminal | `prop_laptop_01a` |
| Power panel | `prop_elecbox_16` |
| Storage | `prop_box_wood04a` |

Both facility sizes reuse the base game **Import / Export vehicle warehouse** (the Finance & Felony DLC garage), loaded by its IPL:

| | Value |
|---|---|
| IPL | `imp_impexp_interior_placement_interior_1_impexp_intwaremed_milo_` |
| Anchor coords | `994.5925, -3002.594, -39.64699` |

Every interior coordinate (entrance, terminal, power panel, storage, and the rig grid) is built around that single verified anchor, so nothing can spawn in the void. A test asserts the IPL is loaded and that every point stays inside the room. The IPL is requested on entry and the interior is refreshed with `RefreshInterior`, so the shell is always solid before the player is teleported in. Routing buckets keep every owner in their own private copy of that shared interior.

**What this means for you:** it works on a vanilla server with zero extra downloads. But these are re-used Rockstar props — a server rack standing in for a mining rig. It is *not* a custom-modelled mining rig or a bespoke MLO like a paid Tebex script would include. If you want custom models, stream your own and change the names in `Config.Props` / `Config.Interiors` (`mlo = true`); the code is built for that and validates every model at runtime, falling back safely if one is missing.

Every model name above is verified by an automated test, so a typo can't silently produce invisible rigs.

---

### Mining rigs (real props)
- Rig chassis, GPU stacks, and cooler props are spawned inside the interior and update live as you install hardware.
- Rig slots are generated as a grid, so a 24-slot warehouse needs zero hand-written coordinates.
- Up to 8 GPUs per rig (configurable).
- **CPU upgrade** — increases the hashrate multiplier.
- **Cooler upgrade** — reduces wear and breakdown chance (spawns a visible fan prop).
- **Durability** degrades over time; worn rigs mine slower and break more often.
- **Disasters** break rigs (with smoke particles) and can destroy a GPU.
- Repair with a repair kit item.

### Economy
- **Dynamic BTC market**: random walk with mean reversion, clamped to a min/max range, persisted in MySQL with price history and trend.
- Live chart in the UI, pushed to every client on each update.
- Configurable exchange fee on every sale.
- **Electricity billing**: base load + per-rig + per-GPU draw, billed per kWh, with automatic power cut when the debt gets too high.
- **Offline mining** with a configurable multiplier, capped at one day of catch-up per tick.
- Optional storage limit per warehouse.

### Shops & NPCs
- **TechShop** — buy and sell GPUs, CPUs, coolers, repair kits.
- **Black market** — robbery tools, paid with dirty money.
- **Informant** — buy the location of a loaded warehouse (never your own), GPS route included.
- **Broker** — buy and sell warehouses.

### Robbery
- Concurrent robberies with a configurable server-wide limit.
- Minimum police requirement, player cooldown, and warehouse cooldown.
- Lockpick + hacking USB requirements, consumed on entry.
- Minigames: **built-in skillcheck** (default, no dependency), plus optional `ox_lib` skill check, `t3_lockpick`, `qb-lockpick`, `howdy-hackminigame`, `memorygame` — auto-detected with a safe fallback.
- Loot each rig once; the job ends automatically when the warehouse is empty or on timeout.
- Owner notification + police dispatch.

### Integrations (all optional, auto-detected)
| Type | Default (zero dependency) | Optional |
|---|---|---|
| Notifications | **built-in toast UI** | `ox_lib`, ESX |
| Progress bar | **built-in progress bar** | `ox_lib`, ESX |
| Skillcheck | **built-in minigame** | `ox_lib`, lockpick/hack resources |
| Target | built-in TextUI fallback | `ox_target`, `qb-target` |
| Inventory | ESX inventory | `ox_inventory` |
| Database | — | `oxmysql`, `mysql-async`, `ghmattimysql` |
| Dispatch | — | `cd_dispatch`, `qs-dispatch`, `ps-dispatch`, `core_dispatch`, `rcore_dispatch`, custom event |

**The only hard requirements are `es_extended` and a MySQL resource (`oxmysql`).** Everything else is optional and degrades gracefully — the notifications, progress bar and robbery skillcheck are all rendered by the resource's own NUI, so **`ox_lib` is not needed**. `ox_inventory` and `ox_target` are used automatically when present.

---

## Installation (copy–paste, 4 steps)

### 1. Copy the folder

Drop the whole `codex_cryptomining` folder into your `resources` directory. Nothing else needs to be copied — there are no streamed files.

### 2. Items

Pick the one line that matches your inventory:

| Your inventory | What to do |
|---|---|
| **ox_inventory** | Copy the contents of `install/ox_inventory_items.lua` into `ox_inventory/data/items.lua` (inside the big `return { ... }` table). **Do not** import `sql/esx_items.sql`. |
| **ESX inventory** | Import `sql/esx_items.sql`. |

The robbery also uses a `lockpick`; most servers already have it. If yours doesn't, uncomment the last block of `sql/esx_items.sql` (or add a lockpick to ox_inventory).

### 3. Database

**Nothing to do** — the four tables are created automatically on first start.

If you prefer to create them yourself, import `sql/codex_cryptomining.sql`. It only contains `CREATE TABLE IF NOT EXISTS`, is safe to re-run, contains no `DELIMITER` or stored procedure, and works in phpMyAdmin, HeidiSQL and the `mysql` CLI.

### 4. server.cfg

```cfg
ensure oxmysql          # or mysql-async / ghmattimysql
ensure es_extended
ensure codex_cryptomining

add_ace group.admin codex_cryptomining.admin allow
```

Order matters: the database and `es_extended` must start **before** this resource.

### Check that it worked

On startup the console must print:

```
[codex_cryptomining] Database ready using oxmysql.
[codex_cryptomining] Started. 5 warehouses, BTC at $42,000.
```

If you instead see one of these, fix it before going further:

| Message | Meaning |
|---|---|
| `No MySQL resource found` | oxmysql / mysql-async / ghmattimysql is not started, or starts after this resource. |
| `es_extended was not found` | ESX is missing or starts too late. |
| `WARNING: OneSync is disabled` | The resource still runs, but server-side distance checks are skipped. Enable OneSync for full anti-cheat protection. |

Then walk to any warehouse blip, or to the broker at the marked location, and buy your first warehouse.

---

## Configuration

Everything lives in `config.lua`. Coordinates you are most likely to change are marked with `-- EDIT`.

### Moving a warehouse

```lua
{
    id = 'elysian',                 -- never change this once players own it
    label = 'Elysian Island Depot',
    type = 'small',                 -- key of Config.Interiors
    price = 185000,
    sellRatio = 0.55,
    entrance = vector4(-41.95, -2530.30, 6.01, 326.0),
    blip = { sprite = 492, color = 5, scale = 0.8 },
    electricity = 1.0               -- local electricity price multiplier
}
```

### Using your own MLO

Set `mlo = true` on the interior, clear the IPL list, and point the coordinates at your MLO:

```lua
Config.Interiors.small = {
    label = 'My custom MLO',
    maxRigs = 20,
    ipls = {},
    mlo = true,                     -- no IPL is requested
    enter    = vector4(...),        -- where the player spawns inside
    terminal = vector4(...),        -- management laptop
    power    = vector4(...),        -- electricity panel
    storage  = vector4(...),        -- storage crate
    slots = {                       -- one entry per rig slot
        { x = 0.0, y = 0.0, z = 0.0, w = 90.0 },
        -- ...
    }
}
```

`slots` accepts either the `GridSlots(...)` helper (auto-generates a grid) or a hand-written list. `maxRigs` is automatically capped to the number of slots you provide.

### Changing the props

```lua
Config.Props.Rig.model = 'prop_server_01'
Config.Props.Gpu.model = 'prop_cs_electronic_junk'
Config.Props.Gpu.perGpuOffset = vector3(0.0, 0.0, 0.11)  -- stacking step
```

Every model is validated at runtime; if a model is missing from the player's game build, `Config.Props.Fallback` is used instead of spawning nothing.

### Tuning the economy

The whole income curve comes down to these values:

```lua
Config.Mining.HashPerGpu      = 25.0        -- MH/s per GPU
Config.Mining.BtcPerHashHour  = 0.0000045   -- BTC per MH/s per hour
Config.Market.StartPrice      = 42000
```

One full rig (8 GPUs, no CPU upgrade) produces
`8 × 25 × 0.0000045 = 0.0009 BTC/h` ≈ **$37/h** at $42,000 per BTC, before electricity.

---

## Commands

| Command | Who | Description |
|---|---|---|
| `/cryptopanel` | everyone | Opens the panel while inside one of your warehouses (fallback if you don't use a target resource). |
| `/crypto price [amount]` | admin | Shows or forces the BTC price. |
| `/crypto info` | admin | Dumps every warehouse to the console. |
| `/crypto reset [id]` | admin | Wipes a warehouse (owner, rigs, wallet). |
| `/crypto setowner [id] [playerId]` | admin | Assigns a warehouse to a player. |

Admin commands require the `codex_cryptomining.admin` ace and also work from the server console.

---

## Exports (server)

```lua
exports.codex_cryptomining:getBitcoinPrice()            --> number
exports.codex_cryptomining:getWarehouseOwner(id)        --> identifier | nil
exports.codex_cryptomining:getWarehouseBalance(id)      --> number (BTC)
exports.codex_cryptomining:isRobberyActive(id)          --> boolean
```

---

## Security model

The client is a renderer; it never decides anything.

- Every action goes through a server callback that re-checks **ownership, keys, distance, item possession and money** before touching any state.
- Quantities are clamped server side, so negative or oversized values are rejected (covered by tests).
- Item and money operations **roll back** if the inventory refuses the transfer, so nothing is ever duplicated or lost.
- One action lock per player prevents callback spam / race conditions.
- Prices, catalogs and rewards are read from the server config only — the client sends an index, never a price.
- Malformed payloads are caught with `pcall` and can never take the resource down.

---

## Tests

The resource ships with a real test suite that boots the actual server scripts on a FiveM/ESX emulator and drives the real NUI in a DOM.

```bash
cd codex_cryptomining

# Server logic - 237 tests (needs lupa: pip install lupa)
python3 tests/run_lua_tests.py
# or, with a system Lua 5.4:
lua tests/run_tests.lua

# Interface - 86 tests (needs jsdom: npm install --no-save jsdom)
node tests/nui_tests.js

# SQL schema & queries - 38 tests (needs sqlglot: pip install sqlglot)
python3 tests/sql_tests.py
```

What is covered: the shipped SQL is parsed with a real MySQL parser and cross-checked against every query in the code (tables, columns, placeholder counts), economy maths, ownership and permissions, GPU/rig limits, negative-quantity and overflow exploits, inventory rollbacks, electricity and auto power cut, disasters and repairs, market bounds over 200 updates, every shop path, the full robbery flow with all its cooldowns, routing buckets, persistence and reload, admin commands, malformed payloads, XSS escaping in the UI, and a 24-hour simulated run checking that no value ever drifts out of range.

Eight real bugs were found and fixed by this suite during development:
1. A `nil` named SQL parameter shifted every following column (an unowned warehouse wrote its owner into the wrong field).
2. `RemoveViewer(nil)` raised a hard `table index is nil` error.
3. Routing buckets were configured but never actually applied.
4. Several prop model names did not exist in GTA V (`prop_server_01`, `prop_cs_electronic_junk`, `prop_fan_02`, `prop_elecbox_16a`) — rigs would have spawned invisible. All names are now verified against the game's object list and locked in by a test.
5. The `mysql-async` path called the `MySQL.Async` global, which only exists if the mysql-async library is added to `server_scripts`. On a mysql-async server every query would have thrown. It now uses exports, so no driver is a hard dependency.
6. `ox_inventory:AddItem/RemoveItem` return `success, response`; the return value was read through `pcall` incorrectly, so a full inventory could be reported as success and duplicate items.
7. Server-side distance checks silently fail without OneSync (every coordinate is 0,0,0), which would have locked every player out of every action. OneSync is now detected, checks degrade safely and the owner is warned in the console.
8. The ESX `items` INSERT lived in the main schema file, so importing it on an ox_inventory server aborted with "Table 'items' doesn't exist". Items now live in a separate `sql/esx_items.sql`.

---

## Credits

Built by **CodeX Community**. Inspired by the feature set of the Advanced CryptoMining release on the Cfx.re forum; this is an independent, original implementation.
