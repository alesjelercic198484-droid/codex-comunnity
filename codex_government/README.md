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

- Job-secured ox_inventory armory at City Hall, opened through ox_target.
- Every `gouv` rank can use every configured police/p_policejob armory item by default (`AllowAllItemsForGovernment = true`).
- Armory includes all items listed in the official p_policejob armory configuration plus flashlight, nightstick, taser, pistol, shotgun, rifle, and ammunition.
- Every government firearm receives a unique server-generated `GOV-` serial number; matching guns already held by `gouv` are updated automatically.
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

## Important: allowing `gouv` to use every police item

Three permissions are involved because ox_inventory, p_policejob, and this resource each have their own configuration. Configure **all three**:

### A. `server.cfg` — ox_inventory police group

This line must appear **before** `ensure ox_inventory`:

```cfg
setr inventory:police ["police", "sheriff", "gouv"]
```

Keep all of your existing police-type jobs in the JSON array. This makes ox_inventory treat `gouv` as a police-capable group for its built-in restricted inventory features.

### B. `p_policejob/shared/config.lua` — p_policejob authorization

At minimum, add this after `Config.Jobs` is defined:

```lua
Config.Jobs['gouv'] = 0
```

To enable its shops, outfits, station features, alerts, and radio channels too, paste the complete supplied snippet at the **end** of `p_policejob/shared/config.lua`:

```text
codex_government/install/p_policejob_config.lua
```

This step is necessary because `p_policejob` is a separate resource with its own private permission checks. A `server.cfg` convar cannot rewrite that resource's Lua `Config.Jobs` table.

### C. `codex_government/config.lua` — all armory items for every rank

The package ships with:

```lua
Config.Armory.AllowAllItemsForGovernment = true
```

When `true`, the registered City Hall shop changes every configured item's minimum grade to `0`. Judge, Prosecutor, Governor, President, Secret Services, and US Marshal can therefore all obtain every configured police item. Set it to `false` only if you want the individual grade requirements in `Config.Armory.Items` to apply.

These permissions authorize the job. The matching p_policejob item definitions must still exist in `ox_inventory/data/items.lua`, as explained below.

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

It also includes standard ox_inventory weapon/ammo entries. Install the item definitions from `p_policejob/INSTALL/ITEMS` as required by p_policejob's own installation guide. **Use p_policejob's official definitions**, because they contain the item callbacks/exports that make equipment functional; a label-only item with the same name is not enough. This resource checks every armory item at startup: an unregistered item is safely skipped and printed in the server console instead of crashing the armory.

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

### 6. Configure `server.cfg`

A complete merge example is supplied at:

```text
codex_government/install/server.cfg.example
```

Copy the relevant lines into your real `server.cfg`. The important rule is that all `inventory:*` convars must be declared before ox_inventory starts:

```cfg
# These must be above `ensure ox_inventory`.
setr inventory:framework "esx"
setr inventory:target true
setr inventory:police ["police", "sheriff", "gouv"]

# Dependencies and framework.
ensure oxmysql
ensure ox_lib
ensure es_extended
ensure ox_target
ensure ox_inventory

# p_policejob dependencies — omit these if you do not own/use it.
ensure p_bridge
ensure p_policejob

# Government resource starts last.
ensure codex_government
```

Do not create a second `inventory:police` line if one already exists. Edit the existing JSON array and append `"gouv"`. Keep sheriff/state police and every other job your server already uses.

### 7. Confirm the all-items option

Open `codex_government/config.lua` and leave this enabled:

```lua
Config.Armory.AllowAllItemsForGovernment = true
```

Restart the server after changing ox_inventory items or job data. Restarting only `codex_government` is sufficient after ordinary armory coordinate/config changes, provided ox_inventory already knows every item.

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

Default access is **all configured items for all `gouv` grades**, because:

```lua
Config.Armory.AllowAllItemsForGovernment = true
```

If you change that option to `false`, these configured minimum grades apply:

- Grade 0: p_policejob field equipment, Government ID, radio, flashlight, normal vest
- Grade 1: nightstick, stun gun, 9mm ammo
- Grade 2: strong vest, combat pistol
- Grade 4: pump shotgun and shotgun ammo
- Grade 5: carbine rifle and rifle ammo

All items, prices, and optional grades are editable in `Config.Armory.Items`. The ox_inventory shop independently enforces the `gouv` job on the server; the ox_target group is not the only security check.

## Government weapon serial numbers

Weapon serial generation is enabled by default:

```lua
Config.WeaponSerials = {
    Enabled = true,
    Prefix = 'GOV',
    UpdateExistingGovernmentWeapons = true,
    ExcludedItems = {
        WEAPON_FLASHLIGHT = true,
        WEAPON_NIGHTSTICK = true
    }
}
```

Every gun issued by the City Hall armory gets a unique server-generated serial in this format:

```text
GOV-69BC1234-25A7F2
```

The serial is generated inside an ox_inventory `createItem` server hook. The City Hall shop sends a private one-use marker, and the hook also recognizes matching configured firearm types created directly in a current `gouv` player's inventory by another shop or server resource. Clients never provide the final number. The ordinary ox_inventory weapon metadata (`durability`, `ammo`, `components`, and registered owner) is preserved.

With `UpdateExistingGovernmentWeapons = true`, the resource also checks matching firearm types already carried by a current `gouv` player:

- when this resource starts;
- when the player loads;
- when their ESX job changes to `gouv`.

Any matching gun without the configured prefix receives a new unique `GOV-` serial. Weapons that already start with `GOV-` keep their number. Flashlights and nightsticks are excluded because they are equipment rather than guns. Add another weapon name to `ExcludedItems` if it should not receive a government serial.

A government-issued weapon keeps its `GOV-` serial if it is later stored, dropped, or transferred. ox_inventory displays the serial through its standard weapon metadata UI.

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

### `gouv` can take an item but cannot use its p_policejob action

Confirm all four points:

1. `setr inventory:police ["police", "sheriff", "gouv"]` is above `ensure ox_inventory`.
2. `Config.Jobs['gouv'] = 0` was added after `Config.Jobs` is created in `p_policejob/shared/config.lua`.
3. The official item entry from `p_policejob/INSTALL/ITEMS` is present in `ox_inventory/data/items.lua`.
4. ox_inventory, p_policejob, and codex_government were restarted after editing.

The `server.cfg` line controls ox_inventory. The `Config.Jobs` line controls p_policejob. Both are required; neither can replace the other.

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
