# QC Vehicle Keys

Advanced Vehicle Keys System for FiveM - Standalone QB-Core with integrated bridge (no p_bridge dependency).

## Features

- **Vehicle Keys**: Item-based keys tied to plate metadata; exports for createKey / removeKey / hasKey
- **NPC Vehicle Theft**: Steal vehicles from NPCs by aiming at the driver with a weapon
- **Lock / Unlock**: Press U to lock/unlock within 15m; animation, horn, indicators; NPC vehicle locking; police/mechanic unlock tool
- **Engine Control**: Press Y to toggle engine; blocks starting without a key; preserves steering wheel angle on exit
- **Lockpick Minigame**: 4 difficulty tiers (3-6 pins, 20-45s), scales by vehicle class; optional lockpick durability
- **Hotwire Minigame**: Difficulty-scaled hotwire sequence; auto-starts engine on success
- **Signal Jammer Minigame**: Required for Expert-tier vehicles; frequency/amplitude matching challenge
- **Police Alerts**: Configurable chance to alert dispatch on failed theft attempt
- **Security Tier Upgrades**: Mechanics install better security to harden vehicles against theft (stored in MySQL)
- **Car Key UI**: Remote lock, trunk, engine, lights, horn, find vehicle, upgrade security; built with React + Mantine

## Dependencies

- **qb-core** (or qc-core)
- **ox_lib**
- **oxmysql**
- **qb-target** or **ox_target** (for target interactions)
- **qb-inventory** or **ox_inventory** (inventory system)
- **ps-dispatch** or **cd_dispatch** or **qs-dispatch** (optional, for police alerts)

## Installation

1. Download and place `qc_vehiclekeys` in your `resources` folder
2. Add `ensure qc_vehiclekeys` to your `server.cfg` (after qb-core, ox_lib, oxmysql)
3. Add items to your QB inventory items list:

### Required Items (add to qb-inventory/shared/items.lua or your inventory items config)

```lua
-- Car Key
['car_key'] = {
    ['name'] = 'car_key',
    ['label'] = 'Car Key',
    ['weight'] = 100,
    ['type'] = 'item',
    ['image'] = 'car_key.png',
    ['unique'] = true,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A vehicle key with plate number attached'
},

-- Lockpick
['lockpick'] = {
    ['name'] = 'lockpick',
    ['label'] = 'Lockpick',
    ['weight'] = 300,
    ['type'] = 'item',
    ['image'] = 'lockpick.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A lockpick for vehicle theft'
},

-- Signal Jammer
['signal_jammer'] = {
    ['name'] = 'signal_jammer',
    ['label'] = 'Signal Jammer',
    ['weight'] = 500,
    ['type'] = 'item',
    ['image'] = 'signal_jammer.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Disables vehicle security systems'
},

-- Security Chips (for upgrades)
['security_chip_1'] = {
    ['name'] = 'security_chip_1',
    ['label'] = 'Security Chip (Basic)',
    ['weight'] = 200,
    ['type'] = 'item',
    ['image'] = 'security_chip_1.png',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = false,
    ['combinable'] = nil,
    ['description'] = 'Basic security upgrade chip'
},
['security_chip_2'] = {
    ['name'] = 'security_chip_2',
    ['label'] = 'Security Chip (Advanced)',
    ['weight'] = 200,
    ['type'] = 'item',
    ['image'] = 'security_chip_2.png',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = false,
    ['combinable'] = nil,
    ['description'] = 'Advanced security upgrade chip'
},
['security_chip_3'] = {
    ['name'] = 'security_chip_3',
    ['label'] = 'Security Chip (Expert)',
    ['weight'] = 200,
    ['type'] = 'item',
    ['image'] = 'security_chip_3.png',
    ['unique'] = false,
    ['useable'] = false,
    ['shouldClose'] = false,
    ['combinable'] = nil,
    ['description'] = 'Expert security upgrade chip'
},
```

4. Add item images to your inventory's `html/images/` folder
5. The script auto-creates the `vehicle_security_tiers` database table on first start

## Configuration

Edit `config/shared.lua` to customize:
- Keybinds (U = lock/unlock, Y = engine toggle)
- Lock settings (animations, bikes, NPC vehicles)
- Engine settings
- Theft/lockpick difficulty per vehicle class
- Security upgrade tiers
- Blacklisted vehicle models

## Exports

### Client
- `exports.qc_vehiclekeys:createKey(plate, entity)` - Create a key for a vehicle
- `exports.qc_vehiclekeys:removeKey(plate, entity, removeAll)` - Remove a key
- `exports.qc_vehiclekeys:StartLockpick(vehicle)` - Start lockpick minigame
- `exports.qc_vehiclekeys:StartHotwire(vehicle)` - Start hotwire minigame
- `exports.qc_vehiclekeys:useCarKey(data, slot)` - Use a car key item

### Server
- `exports.qc_vehiclekeys:changeLockState(playerId, netId, state)` - Change vehicle lock state

## Compatibility

This script provides backward compatibility exports/events for:
- qb-vehiclekeys
- qbx_vehiclekeys
- Renewed-Vehiclekeys
- MrNewbVehicleKeys
- qs-vehiclekeys
- wasabi_carlock

Scripts calling those exports/events will be automatically redirected to qc_vehiclekeys.

## Credits

Based on [p_vehiclekeys](https://github.com/PiotreeQ/p_vehiclekeys) by PiotreeQ.
Bridge layer replaces p_bridge with direct qb-core/qb-inventory/ox_lib integration.