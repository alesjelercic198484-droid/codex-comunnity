# CodeX Black Market (QBCore)

A FiveM black-market resource built specifically for **QBCore**, **qb-inventory**, **qb-target**, and **oxmysql**. The reference video shows a large premium underground economy; this resource recreates its core gameplay loop as an editable, test-ready implementation: restricted black-market shopping, demand-based pricing, reputation progression, cargo contracts, private PIN-protected warehouses, contraband sales, and an in-game market admin panel.

## Included

- Custom dark, responsive NUI terminal with catalog, basket, checkout, cargo runs, selling, profile, warehouse PINs, and admin controls.
- Contact ped and parked van registered through `qb-target`. The contact is shown/interactable between **22:00 and 10:00 GTA world time** by default.
- Restricted catalog with access levels **1–6**. Item availability and all checkout prices are recalculated on the server.
- Persistent stock and configurable scarcity pricing. Market stock replenishes on a timer; administrators can edit live stock and price overrides in-game.
- Cash or bank purchases; the configured sell offers pay cash or bank.
- Three cargo contract tiers, server-validated pickup/drop locations, driver-seat checks, route blips, visible cargo props, refundable completion deposits, and XP/respect rewards.
- Three configurable warehouses. Each character gets an individual six-digit PIN and a separate persistent `qb-inventory` stash at each unlocked location.
- Persistent XP, respect, access level, and completed-run count stored by citizen ID in MySQL.
- Admin command `/bmadmin`, permission-gated by QBCore admin/god permission or ACE `codex_blackmarket.admin`.
- OneSync server-side distance checks for the vendor, delivery stops, and storage terminals.

## Dependencies

Required and started before this resource:

- `qb-core`
- `qb-target`
- `qb-inventory`
- `oxmysql`
- OneSync enabled

No `ox_lib`, `qb-menu`, or other UI resource is needed.

## Installation

1. Copy the `codex_blackmarket` folder into your server's resources directory.
2. Ensure the catalog and sell items exist in `qb-core/shared/items.lua`. The script checks this table at runtime and **hides missing items rather than crashing**. Edit `Config.MarketItems` / `Config.SellOffers` to match your server. An optional set of item entries is in `install/qb_items.lua`; check for duplicates before adding them.
3. Add the following to `server.cfg` in this order (see `install/server.cfg.example`):

   ```cfg
   ensure oxmysql
   ensure qb-core
   ensure qb-target
   ensure qb-inventory
   ensure codex_blackmarket
   set onesync on
   ```

4. The resource creates its three tables automatically with `Config.Database.AutoCreate = true`. If you manage SQL manually, import `sql/codex_blackmarket.sql` and set `AutoCreate = false`.
5. Edit `config.lua` before testing: move the dealer, van, delivery pickup/routes, and warehouses to positions that are valid on your map. Defaults are GTA V coordinates, but may overlap custom MLOs.
6. Restart the resource/server. The startup console lists any missing QBCore catalog items.

Optional admin access:

```cfg
add_ace group.admin codex_blackmarket.admin allow
```

Or grant the ACE directly to an identifier. QBCore `admin` and `god` permissions are also accepted.

## Quick test checklist

1. For an easy first test, temporarily set `Config.MarketHours.Enabled = false`, move `Config.Dealer.Vendors[1].coords` and `vanCoords` to a safe place near you, and move the warehouse/cargo coordinates if needed.
2. Ensure the resource and check the server console for the `Ready` line. Fix any `not in QBCore.Shared.Items` messages by registering the item or removing it from the config.
3. Approach the contact and use **Talk to the black market contact**. Add a catalog item to the basket and check out with cash or bank.
4. Open **Cargo Runs**, accept the Local Courier contract, get into a vehicle as the driver, load the crates at the pickup marker, and complete the handoff shown on the GPS.
5. Complete more contracts to build XP/respect. Higher access levels unlock more products, contracts, and storage.
6. At a warehouse, use **Access … terminal**, enter your displayed PIN, and check that the private stash opens in qb-inventory.
7. Use `/bmadmin` with an authorized character to update stock or set a price override. Set price to `0` to return to the configured base price.

To fund a test character, use your server's normal QBCore admin commands. Item command syntax differs slightly between QBCore versions; commonly it is `/giveitem [id] [item] [amount]`.

## Configuration highlights

All gameplay settings and coordinates are in `config.lua`:

- `Config.Dealer.Vendors`: contact ped, parked van, target range, and coordinates.
- `Config.MarketHours`: GTA world-time availability.
- `Config.Categories` / `Config.MarketItems`: item catalog, access level, base price, starting stock, restock amount, and description.
- `Config.MarketPricing`: scarcity markup and price bounds.
- `Config.Payment.AllowedAccounts`: supported QBCore money accounts (`cash`, `bank` by default).
- `Config.SellOffers`: item buyback prices.
- `Config.Progression.LevelThresholds`: XP required for each access level.
- `Config.Cargo`: pickup, tier deposit/reward/XP, route locations, driver requirement, and marker distances.
- `Config.Warehouses`: private storage coordinates, level, slots, and weight.
- `Config.Security`: server-side interaction distances and transaction quantity limits.

Make sure all catalog item names match the exact lowercase item keys in `qb-core/shared/items.lua`. QBCore weapon items generally use names like `weapon_pistol`.

## Security and operational notes

- The client never supplies a price, reward, stock count, or delivery coordinate. The server resolves those from `config.lua` and validates inventory, access level, money, stock, and current server-side position.
- Checkout debits money first and refunds it if inventory insertion or the persistent stock update fails. Purchases are serialized to prevent simultaneous buyers overselling stock.
- Delivery rewards are granted only after all configured route stops have been reached in order, with the player in a vehicle's driver seat when `RequireDriver = true`.
- Warehouse stashes are keyed by the player's citizen ID; one player's PIN never opens another player's stash.
- The contact's schedule is a roleplay/interaction window enforced by the client presentation. The server still enforces location, item, stock, and payment checks, but does not treat local GTA world time as a security boundary.
- Active cargo contracts are held in memory. A resource restart or player disconnect clears the contract; an uncompleted tier 2/3 deposit is not refunded. Keep this in mind while testing.
- Inventory item icons are provided by your qb-inventory installation. Add images for custom item definitions if you want them shown in that inventory's UI.

## Files

- `client/main.lua` — qb-target, dealer/warehouse interactions, NUI callbacks, mission markers/props.
- `server/main.lua` — database, QBCore money/inventory, progression, stock, mission validation, warehouse PINs, admin controls.
- `html/` — standalone NUI (no UI framework dependency).
- `sql/codex_blackmarket.sql` — schema for manual import.
- `install/` — server.cfg example and optional missing QBCore item entries.
