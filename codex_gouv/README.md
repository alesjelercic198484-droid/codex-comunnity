# CodeX GOUV

A secure ESX government / justice job built for `ox_inventory` and `ox_target`.

## Included

- `gouv` job with grades 0–5: Judge, Prosecutor, Governor, President, Secret Services and US Marshal.
- Government tablet with a live MDT / player directory.
- `/sattelite` tactical player map (the spelling is intentionally kept exactly as requested).
- Green civilian/player markers, blue police markers and red ambulance markers.
- `/gouvmdt` and `/gouvarsenal` commands, plus ox_target tablet and arsenal NPCs.
- Networked tablet prop and tablet animation when the MDT, satellite or arsenal is open.
- Soft cuffs, hard cuffs, remove cuffs and server-validated fines through ox_target.
- Police inventory searches and inventory transfers against a gouv member are blocked by ox_inventory hooks. The police officer receives an automatic server-triggered taze effect.
- Unauthorized police restraint attempts are cleared on the protected player's client and trigger the same taze protocol for nearby police.
- Standard GTA V / ox_inventory weapon arsenal is allow-listed in `config.lua`; an item that is not installed on the server returns a clean error rather than granting an arbitrary item.
- Optional bridge button for an existing police MDT. Every police MDT has a different export/event, so configure it in `Config.MDT.Bridge`.
- All important actions are checked server-side. Client UI visibility is not a permission system.

## Installation

1. Copy `codex_gouv` into your FiveM `resources` directory.
2. Run `sql/gouv.sql` against the same database used by ESX. If your ESX fork has different `skin_male` / `skin_female` columns, remove those two columns and values from the insert or adapt the SQL to that fork.
3. Add this order to `server.cfg`:

```cfg
ensure es_extended
ensure ox_lib              # optional, used for nicer notifications/input dialogs
ensure ox_inventory
ensure ox_target
ensure codex_gouv
```

4. Restart the resource. The supplied defaults are complete for a normal ESX server and place the tablet/arsenal at the configured government building.
5. Only change the job lists if your server uses non-standard job names; common `police`, `sheriff`, `fib`, `ambulance` and `ems` names are already included.

## Government access

Give a player one of the SQL grades with the usual ESX job command/admin tooling:

```text
job: gouv 0  -> Judge
job: gouv 1  -> Prosecutor
job: gouv 2  -> Governor
job: gouv 3  -> President
job: gouv 4  -> Secret Services
job: gouv 5  -> US Marshal
```

Every grade 0–5 can use the government tools. The grade name/label remains available to other resources for custom roleplay permissions.

## Commands and ox_target

- `/sattelite` opens the live satellite map.
- `/gouvmdt` opens the built-in government MDT.
- `/gouvarsenal` opens the arsenal.
- Gouv members can target another player with ox_target for Soft Cuff, Hard Cuff, Issue Fine and Remove Cuffs.
- The two configured NPCs provide the same MDT and arsenal access without relying on a keybind.

## Existing police MDT bridge

The built-in MDT is independent and works without any other MDT. To expose an existing police MDT to gouv members, configure its resource and either a client export or a client event:

```lua
Config.MDT.Bridge = {
    Enabled = true,
    Resource = 'your_mdt_resource',
    Export = true,
    ExportName = 'openMDT',
    ClientEvent = false
}
```

or:

```lua
Config.MDT.Bridge = {
    Enabled = true,
    Resource = 'your_mdt_resource',
    Export = false,
    ExportName = false,
    ClientEvent = 'your_mdt_resource:open'
}
```

Do not guess an event name: use the event/export documented by your installed MDT. The bridge button only appears when enabled.

## Security notes

- `Config.PoliceJobs` is the source of truth for police immunity. Add custom police jobs there.
- The `openInventory` and `swapItems` hooks reject police access to a gouv player's ox_inventory and notify/taze the police player. Hook payload formats can differ slightly between ox_inventory forks; keep the resource's debug output enabled while testing a fork.
- The client restraint watcher is a second line of defence for police scripts that directly set `SetEnableHandcuffs`. It removes the unauthorized local cuff and asks the server to taze police within the configured radius.
- No client event grants an item, cuff or fine. The server validates gouv job, grade, distance, rate limit, target and allow-listed arsenal entry for every action.
- Satellite coordinates are operational data and are intentionally available only to gouv members. The map is a coordinate overlay, so custom maps can adjust `Config.Satellite.MapBounds`.

## ox_inventory items and weapons

The arsenal list is in `config.lua`. Weapons are added as ox_inventory weapon items with `ammo` metadata. The resource automatically discovers every `WEAPON_*` definition available from the installed ox_inventory and also discovers police-labelled items such as cuffs, radios, evidence, body cameras, armour and shields. The explicit fallback list covers normal ESX police item names.

Missing ox_inventory definitions are rejected cleanly by the server; they are never silently created. Custom police item names can still be added to `Config.Armory.Items` if their label does not contain a police keyword.

## Testing checklist

Test on a staging server before production:

1. Join as each gouv grade and confirm `/sattelite`, `/gouvmdt`, `/gouvarsenal`, NPC targets and tablet animation.
2. Confirm the map shows green, blue and red contacts and refreshes after movement.
3. Cuff and fine both civilians and police. Confirm only nearby targets are accepted.
4. As police, try to open a gouv inventory and move an item. Confirm the open/transfer is rejected and the police client is tazed.
5. Test your installed police job's native cuff/search events. Add any custom event names to `blockedPoliceEvents` if its target argument format is different.
6. Try to request an item/weapon from the browser with an arbitrary name. The server must reject it.
7. Disconnect/reconnect and change the player's job while the tablet is open; access must close immediately after the ESX job update.
