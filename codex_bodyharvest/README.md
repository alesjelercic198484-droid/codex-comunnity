# CodeX Body Harvest

An ESX resource by **CodeX Roleplay Development** for `ox_target`, `ox_inventory` and `ox_lib`.

Kill a player, kneel down with a knife and cut off **one finger, one ear and one tongue** per body.
Every cut instantly alerts the police (`Assassination In Progress`, flashing red blip for 90 seconds) and
20 seconds later the whole server is warned that the area became an **OPEN FIRE ZONE** (flashing red circle
on the map). The parts are sold to a hidden dealer in an abandoned mine shaft.

## Features

- **ox_target on dead players** - `Cut the finger`, `Cut the ear`, `Cut the tongue`.
- **One of each part per body.** A finger that was taken is gone for *everybody*, not just for the player
  who took it. A revive / respawn creates a "new body" and resets the three parts.
- **Any knife unlocks it** - `WEAPON_KNIFE`, `WEAPON_DAGGER`, `WEAPON_SWITCHBLADE`, `WEAPON_MACHETE`,
  `WEAPON_BATTLEAXE`, `WEAPON_HATCHET`, `WEAPON_STONE_HATCHET`, `WEAPON_KNIFE_2` or a plain `knife` item
  (`Config.Knives`). No knife = the options are not even shown.
- **Cutting animation** with a knife prop and an `ox_lib` progress circle (6s / 7s / 9s).
- **Items:** `finger`, `ear`, `tongue`.
- **Hidden dealer** (`ox_target`) at an illegal location:
  | Option | Minimum | Price each | Full sale |
  | --- | --- | --- | --- |
  | Sell fingers | 3 | $30,000 | 3 = $90,000 |
  | Sell ears | 3 | $40,000 | 3 = $120,000 |
  | Sell tongues | 3 | $35,000 | 3 = $105,000 |
- **Police alert** to every job in `Config.Alert.Jobs` the moment somebody cuts: notification
  `Assassination In Progress`, dispatch sound and a flashing red blip that lives exactly **90 seconds**.
- **Open fire zone**: **20 seconds** after the police alert every other player gets
  `Police Announcement - This Area is OPEN FIRE ZONE Stay Away!` plus a flashing red circle
  (120m radius, 90 seconds).
- **Server authority**: distance, death state, real ped health, knife, item space, cutting duration,
  cooldowns and one-part-per-body are all validated on the server.

## Installation

1. Copy `codex_bodyharvest` into your `resources` folder.
2. Add the three items from `install/ox_inventory_items.lua` to `ox_inventory/data/items.lua`.
3. Add the resource to your `server.cfg` **after** its dependencies (see `install/server.cfg.example`):

```cfg
ensure es_extended
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure codex_bodyharvest
```

4. Restart the server and give yourself a knife:

```text
/giveitem 1 WEAPON_KNIFE 1
```

## How it plays

1. A player dies. His client replicates the death state, the server double checks the real ped health.
2. Somebody with a knife walks up to the corpse and opens `ox_target` - three options appear.
3. He picks one, kneels down and the progress circle with the cutting animation runs.
4. The server hands out the item, marks that part as taken on that body and fires the police alert.
5. Twenty seconds later the whole server is told to stay away from the area.
6. Once he has at least three of a kind, he drives to the collector and sells them.

## Configuration

Everything is in `config.lua`:

| Setting | What it does |
| --- | --- |
| `Config.Dealer.Coords` | Where the hidden buyer stands. Default: the mine shaft at `-595.19, 2091.56, 131.41`. |
| `Config.Dealer.Account` | `money` (cash), `bank` or `black_money`. Default: cash. |
| `Config.Dealer.SellAll` | `true` = sells the whole stack, `false` = sells exactly the minimum. |
| `Config.Dealer.Blip.Enabled` | The location is meant to be secret, so this is `false`. |
| `Config.Alert.Jobs` | Jobs that get the assassination alert. |
| `Config.Alert.Blip.Duration` | 90 seconds. |
| `Config.Alert.Jitter` | Report the crime a few meters off instead of pin-point. |
| `Config.OpenFireZone.Delay` | 20 seconds after the police alert. |
| `Config.OpenFireZone.Duration` / `Radius` | 90 seconds / 120m. |
| `Config.Parts` | Item, label, icon, animation, prop and duration per body part. |
| `Config.Knives` | Which items count as a knife. |
| `Config.Harvest.*` | Distances, cooldowns, respawn reset and the anti cheat thresholds. |
| `Config.Text` | Every line the player can read. |

## Anti cheat / important notes

- **Nothing is trusted from the client.** The `request` and the `finish` packet are both validated:
  target online, target really dead, distance (`Config.Harvest.ServerDistance`), knife in the inventory,
  part still available and the cut duration (a finish that arrives faster than 85% of the animation is
  dropped).
- **A spoofed death state does not work.** A modified client can set its own state bag, but the server
  also reads the real ped health (`Config.Harvest.ServerHealthCheck`). A player above
  `DeadHealthThreshold` (100) can never be harvested.
  If your ambulance job uses a "last stand" state where the ped keeps health while being down, raise
  `DeadHealthThreshold` (for example to 150) or set `ServerHealthCheck = false`.
- **OneSync must be enabled**, the server side position and health checks depend on it.
- Two players cannot cut the same part at the same time - the part is reserved while it is being cut and
  released again when the cut is cancelled, the player disconnects or the pending timeout expires.
- The item is only marked as taken **after** `ox_inventory` confirmed it was added, so a full inventory
  never destroys a body part.
- A refused sale (too far away, below the minimum) does not start the 5 second dealer cooldown.
- Money is paid with `xPlayer.addAccountMoney`, so it shows up in your ESX logs like any other income.

## Tests / simulation

The resource ships with a FiveM emulator that really executes `client/main.lua` and `server/main.lua`
with four players (killer, victim, officer, civilian):

```bash
lua tests/run_tests.lua        # 111 assertions
lua tests/simulation.lua       # readable minute by minute timeline
```

No system Lua? Use the bundled Python runner (`pip install lupa`):

```bash
python3 tests/run_lua_tests.py             # assertion suite
python3 tests/run_lua_tests.py simulation  # timeline
```

The suite covers the target options, the animation, one-part-per-body, the police alert, the 20 second
open fire zone, blip lifetimes, the dealer economy, respawn resets, disconnects, resource restarts and
every anti cheat guard (instant finish, teleporting away mid cut, spoofed death state, knifeless request,
double cut, remote selling, invalid deal index, full inventory).
