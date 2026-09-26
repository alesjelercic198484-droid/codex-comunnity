# codex_drugmission

A complete English-language FiveM resource for ESX Legacy, ox_lib, ox_target and ox_inventory. It supports multiple server-saved missions, server-side mission state and reward validation, four-seat enemy vehicles, a 20-second head start, a second wave after three minutes, vehicle-abandonment failure, NUI administration and cleanup.

## Installation

1. Copy `codex_drugmission` into `resources/[codex]/`.
2. Ensure dependencies before this resource in `server.cfg`:

```cfg
ensure oxmysql                 # only if your ESX installation needs it
ensure ox_lib
ensure es_extended
ensure ox_target
ensure ox_inventory
add_ace group.admin codex.drugmission allow
ensure codex_drugmission
```

No SQL is required. Mission data is saved to `data/missions.json` with `SaveResourceFile`. The included file is a fallback seed; the first save writes the configured missions there.

3. `/drugmission` is restricted to ESX `admin`/`superadmin` groups or the `codex.drugmission` ACE permission. Change `Config.AdminGroups` or `Config.AdminAce` in `config.lua` if necessary.

## Creating the first mission

1. Join as an authorised administrator and run `/drugmission`.
2. Click **New mission**, enter a name and a short ID.
3. Stand at the mission NPC and click **Set NPC position**.
4. Stand at the vehicle spawn and click **Set vehicle spawn**.
5. Stand at the delivery point and click **Set destination**.
6. Stand at the handover point and click **Set reward NPC position**.
7. Enter valid GTA model names for the delivery vehicle and waves. Each wave can have two vehicles and up to four NPCs per vehicle. `WEAPON_MICROSMG` is the default.
8. Add one or more rewards and click **Save mission**.

Coordinates are captured from the administrator's current position. The UI accepts multiple missions and can load any saved mission from its selector.

## Rewards and ox_inventory

`cash`, `bank` and `black_money` rewards are paid as ESX accounts on the server. An `item` reward is inserted with ox_inventory and is checked with `CanCarryItem` first. An item called `black_money` is **not** automatically supplied by ox_inventory; if you want it as an item rather than the ESX account, define it in your ox_inventory items configuration, for example:

```lua
['black_money'] = {
    label = 'Marked Cash', weight = 0, stack = true, close = true,
    description = 'Illegal cash'
},
```

Use reward type `item` for that item, or reward type `black_money` for the ESX account. `ammo-9` and other items must also exist in your ox_inventory item definitions.

## Mission flow

The client only requests actions. The server owns the active token, selected mission, vehicle network ID, destination checks, player seat checks, state and one-time reward flag. Enemy creation is only requested after a server-authorised mission is active and enemy network IDs are reported back to the server. Completing with a fake event, vehicle or coordinate is rejected.

A delivery vehicle is created as a networked entity. The driver must be in the mission vehicle at the destination. Leaving it starts a two-minute countdown with ten-second notices; the 60-second notice also attempts to play `sounds/hurry.ogg`. The included English voice files are played through the NUI:

- `sounds/dialogue_start.mp3`
- `sounds/dialogue_brave.mp3`
- `sounds/dialogue_not_ready.mp3`
- `sounds/dialogue_challenge.mp3`
- `sounds/dialogue_decline.mp3`
- `sounds/hurry.mp3`

If any audio file is removed, the text dialogue and notification still work.

## Testing checklist

- Restart the resource and confirm saved missions remain.
- Test both dialog responses.
- Confirm the vehicle is networked and the first wave waits 20 seconds.
- Drive away from the vehicle and return before two minutes.
- Wait three minutes after the first wave for the second wave.
- Test death, vehicle destruction, disconnect, resource restart and destination completion.
- Confirm the reward arrives exactly once and an item reward is rejected safely when the inventory is full.

All user-facing script messages, dialogue, audio and the administration panel are in English.
