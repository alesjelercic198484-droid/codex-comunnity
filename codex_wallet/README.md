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
  cash items out of the inventory, "To inventory" puts them back. Nothing is
  created or destroyed. (Classic QBCore money-account mode is also supported,
  see *Money modes* below.)
- **Documents**: store ID cards, driver licences, weapon licences and any
  custom whitelisted item inside the wallet and take them out again.
- **Show ID**: present any stored document to all nearby players (read-only
  popup with name, DOB, gender, nationality and document number).
- Configurable **slots** (default 8) and **weight** capacity (default 2 kg).

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
| Test kit (admins) | `/wallettest` — gives a wallet, sample ID cards and $5,000 cash |

## Money modes

Configured in `Config.Money`:

| Mode | Behaviour |
|---|---|
| `'item'` *(default)* | Cash is an **inventory item**. "To wallet" removes cash items from the inventory into the wallet; "To inventory" gives cash items back. Multiple stacks are merged/drained correctly. |
| `'account'` | Classic QBCore behaviour: cash moves between the `cash` **money account** and the wallet. |

Item-mode settings:

```lua
Config.Money = {
    Mode = 'item',          -- 'item' or 'account'
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
(both money modes), multi-stack cash handling, whitelist enforcement,
wallet-in-wallet prevention, presentation radius, rate limiting, logging,
persistence and the client shell. **114 assertions.**

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

Configured in `Config.AllowedItems` — add your own documents easily:

```lua
['police_badge'] = {
    label = 'Police Badge',
    weight = 50,
    presentable = true   -- can be shown to nearby players
},
```

`presentable = false` items can be stored but never shown to others. The
wallet item itself is never allowed inside a wallet.

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

## License

Made for the CodeX Community. Support our community and unlock amazing perks!
