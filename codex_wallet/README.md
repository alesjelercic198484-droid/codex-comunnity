# codex_wallet — CodeX Wallet

**Advanced wallet system for QBCore.** Players can keep **cash** and **ID
cards / documents** inside a premium leather wallet branded **CodeX Wallet** —
store it, open it, deposit money, stash your ID cards and show them to nearby
players like in real life.

![CodeX Wallet](install/wallet_preview.png)

Inspired by the Atomic Wallet showcase (ESX / QBCore) — rebuilt from scratch
for **qb-core** with a CodeX look.

## Features

### 💼 Intelligent wallet management
- Usable `codex_wallet` item (plus `/wallet` command and a rebindable keybind,
  default **F7**) opens a premium **CodeX Wallet** NUI.
- **Cash**: moves between your **inventory** and the wallet — "To wallet" takes
  cash items out of the inventory, "To inventory" puts them back. The wallet is
  **never linked to a bank or money account** — only what physically sits in
  your inventory can go inside.
- **Documents**: store ID cards, driver licences, weapon licences, bank cards,
  police badges, credit cards and any custom whitelisted item inside the wallet
  and take them out again.
- **Show ID**: present any stored document to all nearby players (read-only
  popup with name, DOB, gender, nationality and document number).
- Configurable **slots** (default 8) and **weight** capacity (default 2 kg).

### 🛠️ WAdmin panel (in-game whitelist management)
- Admin command `/walletadmin` opens the **WAdmin** NUI.
- Add any new item by its **spawn code** (e.g. `creditcard`) — label, weight
  and "presentable" toggle — and it can immediately be stored in every wallet.
- Enable / disable / remove entries at runtime; changes persist in the
  `codex_wallet_whitelist` table and survive restarts.
- Quick-add chips for common items (`creditcard`, `bank_card`, `police_badge`...).
- Permission: QBCore admin/god or ACE `codexwallet.admin`.

### 🔒 Advanced security (server-authoritative)
- **Item whitelist** — only configured documents can be stored
  (`Config.AllowedItems`).
- **Wallet-in-wallet prevention** — a wallet can never be stored inside
  another wallet (anti infinite-storage exploit).
- Every action is validated server-side: ownership of the wallet item,
  duplicate protection, slot/weight caps, per-operation money caps,
  and a **rate limiter** (default 250 ms).
- Anti-dupe flow: money/items move first, wallet bookkeeping is rolled back if
  persistence fails.

### 📊 Professional logging system
- Every wallet action (open, deposit, withdraw, store, remove, present, and
  every rejected exploit attempt) is logged.
- **3 destinations**: server console, resource log file (`logs/wallet.log`),
  Discord webhook.
- **4 log levels**: `DEBUG`, `INFO`, `WARN`, `ERROR` (`Config.Logging.Level`).

### ⚙️ Fully configurable
- Branding (`Config.Brand`), capacity, money limits, whitelist, commands,
  keybind, presentation radius, notifications — all in `config.lua`.

## Requirements

- `qb-core`
- `oxmysql`
- `qb-inventory` (default) **or** `ox_inventory` (`Config.Inventory = 'auto'`
  picks it up automatically)

## Installation

### 1. Copy the resource

Copy the `codex_wallet` folder into your server `resources` directory and add
this to `server.cfg` (see `install/server.cfg.example`):

```cfg
ensure oxmysql
ensure qb-core
ensure qb-inventory
ensure codex_wallet
```

### 2. Import the SQL

Import `install/codex_wallet.sql` into your server database. It creates the
`codex_wallets` table that stores wallet cash and documents (keyed by a serial
number held in the item metadata).

### 3. Register the item (qb-inventory)

Paste the entry from `install/qb_items.lua` **inside the table** in
`qb-core/shared/items.lua` (or your qb-inventory items file):

```lua
['codex_wallet'] = {
    name = 'codex_wallet',
    label = 'CodeX Wallet',
    weight = 200,
    type = 'item',
    image = 'wallet.png',
    unique = true,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'A premium leather wallet branded CodeX Wallet. Store your ID cards and cash safely inside.'
},
```

> Using **ox_inventory** instead? Paste `install/ox_inventory_items.lua` into
> `ox_inventory/data/items.lua`.

### 4. Copy the wallet images

Copy the wallet images from the `install/` folder into your inventory's image
folder:

| File | Copy to |
|---|---|
| `install/wallet.png` | `qb-inventory/html/images/wallet.png` |
| `install/wallet.png` (ox) | `ox_inventory/web/images/wallet.png` |
| `install/wallet_preview.png` | *(optional)* store/preview banner |

`install/wallet.png` is the in-inventory icon, `install/wallet_preview.png`
is the showcase banner (also used in this README).

### 5. Optional: Discord webhook & permissions

```cfg
set codex_wallet:webhook "https://discord.com/api/webhooks/XXXX/YYYY"
add_ace group.admin codexwallet.admin allow
```

The webhook can also be set in `config.lua` (`Config.Logging.Webhook`).

## Usage

| Action | How |
|---|---|
| Open wallet | Use the **CodeX Wallet** item, type `/wallet`, or press **F7** |
| Cash into wallet | Enter an amount (or leave empty for max) and press **To wallet ▸** |
| Cash into inventory | Enter an amount (or leave empty for max) and press **◂ To inventory** |
| Store a document | Press **Store** next to an item in the *Store from inventory* list |
| Show a document | Press **Show ID** on a card inside the wallet — every nearby player sees it |
| Remove a document | Press **Remove** on a card — it returns to the inventory |
| Manage whitelist (admins) | `/walletadmin` — add items by spawn code, enable/disable/remove |
| Test kit (admins) | `/wallettest` — gives a wallet, sample ID cards, bank card and $5,000 cash |

## Money (inventory only — no bank!)

The wallet is **strictly inventory-based**: cash is an inventory item and only
ever moves inventory ⇄ wallet. The bank, money accounts and society funds are
never touched.

```lua
Config.Money = {
    ItemName = 'cash',      -- your money item (e.g. 'cash', 'money', 'black_money')
    ItemLabel = 'Cash',
    ...
}
```

If your server does not have a money item yet, paste the optional `cash`
example from `install/qb_items.lua` into your items file. If your money item
is called differently, just change `Config.Money.ItemName` — no other edits
are needed.

## Testing (bug-check suite)

The resource ships with a full mock-based test suite that executes the real
`server/main.lua` and `client/main.lua` and asserts money conservation
(inventory-only, multi-stack cash), whitelist enforcement, WAdmin spawn-code
management (add/toggle/remove), wallet-in-wallet prevention, presentation
radius, rate limiting, logging, persistence and the client shell.
**135 assertions.**

```bash
pip install lupa
cd codex_wallet
python3 tests/run_lua_tests.py       # or:  lua tests/run_tests.lua
```

In-game testing:

1. Make yourself admin (`add_ace group.admin codexwallet.admin allow` or
   QBCore admin permission).
2. Run `/wallettest` — you receive a wallet, ID Card, Driver Licence, Weapon
   Licence and $5,000 cash.
3. Open the wallet (item / `/wallet` / F7) and try depositing, storing your
   documents, showing them to another player and removing them again.

## Item whitelist (documents)

Managed at runtime in the **WAdmin panel** (`/walletadmin`) and seeded from
`Config.AllowedItems` — defaults include `id_card`, `driver_license`,
`weaponlicense`, `government_id`, `dos_id_card`, `police_badge`, `bank_card`
and `creditcard`.

Adding a brand new item in WAdmin is one field — its spawn code:

| Field | Meaning |
|---|---|
| Spawn code | inventory item name, e.g. `creditcard` |
| Label | display name in the wallet |
| Weight (g) | counted against the wallet weight cap |
| Presentable | can the owner show it to nearby players |

`presentable = false` items can be stored but never shown to others. The
wallet item itself is never allowed inside a wallet. Removing a config-default
entry in WAdmin disables it (the config seed stays intact).

## Data model

Each wallet carries a unique `serial` (e.g. `CXW-12345678`) in its item
metadata. Contents (cash + documents) live in the `codex_wallets` table:

| Column | Meaning |
|---|---|
| `serial` | wallet id (primary key) |
| `cash` | cash stored inside the wallet |
| `items` | JSON list of documents (with their metadata snapshots) |
| `owner` | last known owner (informational) |

Because contents follow the serial (not the player), wallets can be traded,
dropped and recovered without losing anything.

## Exports

```lua
exports['codex_wallet']:OpenWallet(source)        -- open a player's wallet
exports['codex_wallet']:GetWalletData(serial)     -- read wallet contents
exports['codex_wallet']:GiveTestKit(source)       -- issue the admin test kit
```

| Table | Meaning |
|---|---|
| `codex_wallets` | wallet contents (cash + documents) keyed by serial |
| `codex_wallet_whitelist` | items allowed in the wallet (WAdmin-managed) |

## License

Made for the CodeX Community. Support our community and unlock amazing perks!
