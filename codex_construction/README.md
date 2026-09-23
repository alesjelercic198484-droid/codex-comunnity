# CodeX Construction

A copy-paste ESX construction contract resource by **CodeX Roleplay Development**. It is designed around the construction tablet shown in the supplied reference video: a modern tablet NUI, contract flow, work points with physical props, and a small multiplayer crew.

## Features

- ESX, `ox_target`, and `ox_inventory`.
- No job or job grade is required.
- One live contract can contain up to **4 players**.
- Crew leader creates and starts the contract; other players join from the foreman tablet.
- Eight physical construction props, each with an ox_target work interaction.
- Every worker receives a separate task list. Tasks are validated server-side by distance and inventory.
- Requires one `construction_tools` item per completed task (the item is consumed by default).
- Contract lasts exactly 10 minutes and pays **€12,000 bank money to every crew member** when the timer ends.
- Server-side spam locks, player drop cleanup, distance validation, max crew validation, and payout protection.
- All site coordinates, prop models, payout, duration and item settings are in `config.lua`.

## Installation

1. Copy `codex_construction` into your resources folder.
2. Add the item in `install/ox_inventory_items.lua` to `ox_inventory/data/items.lua`.
3. Ensure dependencies before this resource:

```cfg
ensure oxmysql
ensure es_extended
ensure ox_inventory
ensure ox_target
ensure codex_construction
```

4. Restart the server. Edit `Config.Foreman` and `Config.Tasks` if your map uses different coordinates.
5. Give players the tool item, for example using your normal ox_inventory admin command:

```text
/giveitem 1 construction_tools 10
```

## How to play

Go to the foreman and use **Open construction tablet**. Create a crew, let up to three other players use **Join crew**, and press **Start contract**. Every player works their assigned highlighted work points. The payout is issued when the ten-minute contract reaches zero.

## Important notes / checks

- The client only displays props and requests an action. The server checks the player position, assignment, active session, item count and crew membership before consuming an item or changing progress.
- A dropped player is removed from the crew; if everyone leaves, the session is deleted. A resource restart also clears the in-memory session safely.
- This resource intentionally does not alter `xPlayer.setJob` and does not require a construction job.
- Make sure `ox_inventory` is started before this resource. If you use a custom item system, change `Config.RequireItem` and the server inventory calls together.
- The included `prop_cementmixer01a` model is commonly available in GTA/FiveM builds. If your server has a custom prop pack, change that model in `Config.Tasks`.
