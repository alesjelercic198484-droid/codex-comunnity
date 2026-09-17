# CodeX Daily Missions

Professional ESX daily missions / timed rewards resource for FiveM.

This is an original open-source style implementation inspired by daily mission systems: players stay online, progress is saved, completed rewards remain claimable after reconnects, and unfinished daily progress resets when the next daily cycle starts.

## Features

- ESX / ESX Legacy compatible.
- Built for `ox_inventory` item/weapon rewards.
- Built for `ox_target` NPC interaction.
- Works with `oxmysql`, `mysql-async`, or `ghmattimysql`.
- Automatic SQL table creation, plus a manual SQL file.
- Responsive NUI dashboard.
- Mission ped opens the menu through ox_target.
- Optional fallback command: `/dailymissions` by default.
- No default F7 keybind or any other keybind.
- Persistent progress across disconnect/reconnect.
- Completed rewards stay available until claimed.
- Unfinished missions automatically roll over/reset on the next daily cycle.
- Configurable simultaneous or sequential mission progression.
- Reward types: cash, bank/account, items, weapons, commands, and optional vehicle SQL rewards.
- Claim lock protection to prevent double-claim spam.
- Optional heartbeat setting for anti-AFK style counting.

## Installation

1. Extract `codex_daily_missions` into your FiveM server `resources` folder.
2. Make sure these resources are installed and started before this resource:
   - `es_extended`
   - `ox_inventory`
   - `ox_target`
   - one supported MySQL resource: `oxmysql` recommended, or `mysql-async`, or `ghmattimysql`
3. Add this to your `server.cfg`:

```cfg
ensure es_extended
ensure oxmysql
ensure ox_inventory
ensure ox_target
ensure codex_daily_missions
```

4. If `Config.Database.AutoCreate = true`, the table is created automatically.
   If you prefer manual SQL, import:

```sql
codex_daily_missions/sql/codex_daily_missions.sql
```

5. Edit `config.lua` to change rewards, times, reset hour, colors, command, keybind, etc.
6. Restart your server.

## Configuration notes

### ox_target mission ped

The menu opens by targeting the NPC with ox_target. Change the ped location in `config.lua`:

```lua
Config.MissionPed = {
    Enabled = true,
    Model = 'a_m_m_business_01',
    Coords = vector4(215.76, -810.12, 30.73, 340.0),
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    Distance = 2.0,
    Target = {
        Label = 'Open Daily Missions',
        Icon = 'fa-solid fa-calendar-check'
    }
}
```

### Keybinds and command

No default keybind is registered. The script opens through the ox_target ped.

The `/dailymissions` command is left enabled as a fallback. To disable it completely:

```lua
Config.OpenCommand = false
```

### ox_inventory

Item rewards and weapon rewards use `ox_inventory` first:

```lua
Config.Inventory = {
    Type = 'ox_inventory',
    AllowESXFallback = true,
    WeaponAsItem = true
}
```

For ox_inventory, make sure every configured item exists in `ox_inventory/data/items.lua`.

### Mission times

Times are in seconds:

```lua
requiredSeconds = 45 * 60 -- 45 minutes
```

### Progress mode

```lua
Config.Progress.Mode = 'all'
```

- `all`: every unfinished mission counts at the same time.
- `sequential`: only the first unfinished mission counts; the next starts when the previous is completed.

### Daily reset

```lua
Config.Reset = {
    Timezone = 'local', -- local or utc
    Hour = 0           -- midnight
}
```

Old unfinished missions stop being shown after the daily reset. Old completed but unclaimed missions remain visible in the **Unclaimed** tab.

## Reward examples

```lua
{ type = 'money', amount = 2500, label = '$2,500 Cash' }
{ type = 'account', account = 'bank', amount = 7500, label = '$7,500 Bank' }
{ type = 'item', name = 'repairkit', count = 1, label = 'Repair Kit' }
{ type = 'weapon', name = 'WEAPON_PISTOL', ammo = 24, label = 'Pistol' }
{ type = 'command', command = 'giveitem {source} phone 1', label = 'Phone' }
```

Command placeholders:

- `{source}`
- `{identifier}`
- `{playerName}`
- `{missionKey}`
- `{dayKey}`
- `{amount}`
- `{name}`

## Optional vehicle rewards

Vehicle rewards are disabled by default because ESX `owned_vehicles` schemas differ between servers.

To enable:

1. Set `Config.VehicleRewards.Enabled = true`.
2. Confirm `Config.VehicleRewards.InsertSQL` matches your `owned_vehicles` table.
3. Add a reward like:

```lua
{ type = 'vehicle', model = 'sultan', label = 'Sultan' }
```

## Client exports

```lua
exports['codex_daily_missions']:OpenDailyMissions()
exports['codex_daily_missions']:CloseDailyMissions()
```

## Troubleshooting

- If the UI says data is loading, confirm `es_extended` and your MySQL resource start before this script.
- If item claiming fails, your inventory is full or the configured item name does not exist.
- If you use an old ESX version, set `Config.ESX.UseExport = false`.
- If using vehicle rewards, test the configured `InsertSQL` against your exact garage schema first.
