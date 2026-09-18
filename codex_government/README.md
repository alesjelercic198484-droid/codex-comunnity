# codex_government

A server-authoritative ESX government resource built for **ox_inventory**, **ox_target**, **ox_lib**, and optional **p_policejob** integration.

## Features

- Exact `gouv` ranks requested:

  | Grade | Internal name | Label |
  |---:|---|---|
  | 0 | `judge` | Judge |
  | 1 | `prosecutor` | Prosecutor |
  | 2 | `governor` | Governor |
  | 3 | `president` | President |
  | 4 | `secret service` | Secret Services |
  | 5 | `us marshal` | US Marshal |

- Grade-secured ox_inventory armory at City Hall, opened through ox_target.
- Armory includes all items listed in the official p_policejob armory configuration plus flashlight, nightstick, taser, pistol, shotgun, rifle, and ammunition.
- Live, flashing police and EMS blips visible **only** to `gouv` players.
- Professional Government ID NUI with no player photograph.
- ID can be used from ox_inventory to show every nearby player, or presented to one player through ox_target.
- Government ID data is generated server-side from ESX identity/job data.
- Government officials are protected from cuffing. p_policejob wrappers block the action before it starts and can tase/ragdoll a police attacker.
- Defense-in-depth cuff safety net for native and p_policejob-compatible state bags.
- Server validation for jobs, item ownership, distance, armory access, and cuff-attempt penalties.
- No SQL queries run during gameplay and no idle per-frame loops except while the ID has focus or a tase penalty is active.

## Requirements

- ESX Legacy (`es_extended`)
- `ox_lib`
- `ox_inventory`
- `ox_target`
- OneSync (required for secure server-side distance and emergency-unit coordinates)
- Optional but supported: `p_policejob` and its dependencies

## Installation

### 1. Install the resource

Copy `codex_government` into your server's resources folder.

### 2. Import the ESX job

Import:

```text
codex_government/install/codex_government.sql
```

The installer updates existing `gouv` grade names/labels and inserts missing grades. It preserves salaries on existing grades; new grades start with salary `0` so the script does not unexpectedly change your server economy.

After importing, restart ESX/server so the job cache reloads.

### 3. Add the Government ID to ox_inventory

Paste the entry from:

```text
codex_government/install/ox_inventory_items.lua
```

inside the table in:

```text
ox_inventory/data/items.lua
```

Copy:

```text
codex_government/install/government_id.png
```

to:

```text
ox_inventory/web/images/government_id.png
```

The item has `consume = 0`: presenting it never deletes it.

### 4. Verify p_policejob items

The armory uses the official p_policejob item names:

```text
spike_strip, police_diving_suit, tracking_band, fingerprinter,
stick_bag, stick, body_cam, gps, camera, radio, handcuffs,
vest_normal, vest_strong
```

It also includes standard ox_inventory weapon/ammo entries. Install the item definitions from `p_policejob/INSTALL/ITEMS` as required by p_policejob's own installation guide. This resource checks every armory item at startup: an unregistered item is safely skipped and printed in the server console instead of crashing the armory.

### 5. Configure p_policejob access and cuff protection

Follow:

```text
codex_government/install/P_POLICEJOB_INTEGRATION.md
```

This is required for guaranteed prevention inside the separate p_policejob resource. At minimum, merge these entries into its editable config:

```lua
Config.Jobs['gouv'] = 0
Config.OutfitsAccess['gouv'] = 0
```

Replace direct p_policejob cuff calls in your menu/radial/target with:

```lua
TriggerEvent('codex_government:client:protectedHardCuff')
TriggerEvent('codex_government:client:protectedSoftCuff')
```

The wrappers use the exported protection check before p_policejob starts cuffing. The included safety net is a fallback, not a substitute for guarding the external resource's call site.

### 6. Configure ox_inventory police jobs

Before `ensure ox_inventory` in `server.cfg`, merge `gouv` into the inventory police-job list:

```cfg
setr inventory:police ["police", "gouv"]
```

Keep any additional police/sheriff jobs already used by your server.

### 7. Start resources in order

Example:

```cfg
ensure ox_lib
ensure es_extended
ensure ox_target
ensure ox_inventory
ensure p_bridge
ensure p_policejob
ensure codex_government
```

Only include `p_bridge` / `p_policejob` if installed.

### 8. Give the item

Use your admin inventory tooling to give an authorized employee:

```text
government_id
```

Assign their ESX job and grade using your normal admin/job-management tools, for example job `gouv`, grade `4` for Secret Services.

## City Hall armory

The default target location is:

```lua
vector3(-545.38, -204.03, 38.22)
```

This is a generic City Hall exterior coordinate. Every City Hall MLO has a different interior. Change `Config.Armory.Coords`, `Size`, and `Rotation` in `config.lua` to match yours.

Default grade access:

- Grade 0: p_policejob field equipment, radio, ID tools, flashlight, normal vest
- Grade 1: nightstick, stun gun, 9mm ammo
- Grade 2: strong vest, combat pistol
- Grade 4: pump shotgun and shotgun ammo
- Grade 5: carbine rifle and rifle ammo

All items/prices/grades are editable in `Config.Armory.Items`. The ox_inventory shop independently enforces `gouv` access on the server; the ox_target group is not the only security check.

## Emergency blips

`gouv` players receive current server-side positions for jobs listed under `Config.Tracking.Jobs` (defaults: `police` and `ambulance`). Other players never receive this payload. Blips:

- flash every 900 ms;
- update every 2 seconds;
- expire automatically if updates stop;
- show roleplay names and server IDs by default;
- clear immediately when the local player leaves `gouv`.

Set `ShowPlayerNames = false` to hide names, or edit sprites/colors in `config.lua`.

## Government ID

Using `government_id` from ox_inventory:

1. ox_inventory invokes the client export and its secure server callback;
2. the server verifies the real ESX job and inventory item;
3. the holder sees the credential with NUI focus;
4. every player within the configured radius receives a read-only version for 12 seconds.

A `gouv` player carrying the item can also target one player with ox_target and choose **Present Government ID**. All names are inserted using `textContent`, not HTML, and the raw ESX identifier is never sent to clients. A deterministic public credential number is sent instead.

## Cuff-protection API

Client (also reports a blocked attempt for secure server validation):

```lua
local allowed = exports['codex_government']:CanCuff(targetServerId)
```

Client read-only check:

```lua
local protected = exports['codex_government']:IsGovernmentProtected(targetServerId)
```

Server:

```lua
local protected = exports['codex_government']:IsGovernmentPlayer(targetServerId)
local allowed = exports['codex_government']:CanCuff(targetServerId)
exports['codex_government']:ReportCuffAttempt(attackerServerId, targetServerId)
```

The server validates that the attacker has a configured police job, the target is currently `gouv`, and both players are within range before applying any penalty. A client cannot tase another player by sending arbitrary IDs.

## Troubleshooting

### Armory item missing

Read the startup console line beginning with:

```text
[codex_government] Armory skipped unregistered ox_inventory items
```

Add those definitions from the official p_policejob installer to `ox_inventory/data/items.lua`, then restart ox_inventory/server and this resource.

### Government ID does nothing

Confirm the item entry uses dot-separated exports exactly:

```lua
client = { export = 'codex_government.governmentId' }
server = { export = 'codex_government.useGovernmentId' }
```

Confirm `codex_government` is running and the player's current ESX job is exactly `gouv`.

### Police can still begin p_policejob cuffing

The external p_policejob call site has not been switched to the protected wrapper. Follow `install/P_POLICEJOB_INTEGRATION.md`. A separate resource cannot cancel an escrow resource's private code before it runs without that integration point.

### No blips

Confirm OneSync is enabled, the viewer is currently `gouv`, and tracked players use exactly `police` / `ambulance` (or update `Config.Tracking.Jobs` to your real names).

## Configuration

All gameplay, location, item, permission, timing, blip, NUI, and notification settings are centralized in `config.lua`.
