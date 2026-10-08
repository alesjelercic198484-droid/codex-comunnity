# CodeX Banking for QBCore

**CodeX Banking** is a standalone FiveM banking resource for QBCore. It is an original implementation inspired by the feature set shown in the reference video; it is not a copy of, or an official product from, CodeM. The NUI and all player-facing messages are in English.

## Features

- **QBCore and oxmysql integration.** `ox_lib`, `ox_target`, and `qb-target` are not required. The banking UI, markers, and key prompts are included.
- **Three bank networks:** Fleeca, Maze Bank, and Pacific Standard, with nine configurable branches, account-number prefixes, opening fees, limits, and ATM fees.
- **Personal, savings, shared, and company accounts.** Shared accounts support owners, admins, members, and read-only members, with per-member permissions and daily limits.
- **QBCore bank-balance compatibility.** On first use, the player's existing `PlayerData.money.bank` balance is imported into a personal CodeX checking account. Personal checking and savings balances are then mirrored to QBCore's `bank` balance for other resources using `AddMoney` and `RemoveMoney`. Shared and company balances are not counted in that mirror.
- **Deposits, withdrawals, transfers, and transaction history.** IBAN transfers work while the recipient is offline. The default inter-bank fee is 0.5%, with a $5,000,000 daily transfer cap.
- **Standard, Gold, Platinum, and Black cards.** Cards use four-digit PINs, lock after three failed attempts for five minutes, can be frozen, and have tier-specific daily withdrawal limits.
- **ATMs.** Card-based cash withdrawals, fees, card limits, 29 configurable access points, player ownership, owner surcharges from 0–3%, and collection of ATM earnings.
- **Savings accounts.** Four configurable tiers, savings goals, and daily interest after at least 60 minutes of tracked activity that day.
- **Loans.** Personal, vehicle-secured, and business plans. Credit scores (300–850) affect rates; missed payments add penalties, lower credit scores, and can trigger vehicle repossession.
- **Invoices and cheques.** Invoices can be issued by Citizen ID and paid from an accessible account. Cheques can be bearer or named, expire after seven days, and can bounce if funds are unavailable.
- **Safe deposit boxes.** Configurable rental tiers and inventory stashes. `ox_inventory` and common `qb-inventory` stash APIs are supported; one of these resources must be running to rent or open a box.
- **`/bankadmin`.** Review ledger totals, loans, ATMs, fees, and recent transactions; change the inter-bank fee at runtime and persist it to SQL.
- **Server-side validation.** Branch/ATM distance, sessions, accounts, cards, membership, amounts, limits, balances, and permissions are checked on the server. Financial writes are serialized and stored in MySQL transactions.
- **Exports for other scripts:** `GetAccountBalance(accountNo)`, `GetJobAccountBalance(jobName)`, `AddJobMoney(jobName, amount, reason, actorCid)`, and `RemoveJobMoney(jobName, amount, reason, actorCid)`.

## Installation

1. Copy `codex_banking` into your server's `resources` directory.
2. Start **oxmysql** and **qb-core** before `codex_banking`. The resource creates its tables automatically by default (`Config.Database.AutoCreate = true`). If automatic schema creation is disabled, import `sql/codex_banking.sql` first.
3. Copy the relevant lines from `install/server.cfg.example` into `server.cfg`. Set a long, random `codex_banking:pinSecret`; do not use the example value or a public value.
4. Stop any other banking resource/UI that registers `/bank` or intercepts the same banking events (for example, `qb-banking`) to avoid duplicate interfaces.
5. Start `qb-inventory` or `ox_inventory` before this resource if you want to use safe deposit boxes.
6. Restart the server and visit a branch. The first personal checking account is created on the first branch visit, and the existing QBCore bank balance is imported when legacy sync is enabled.

Example startup order:

```cfg
set codex_banking:pinSecret "SET_A_LONG_RANDOM_SECRET_HERE"
ensure oxmysql
ensure qb-core
ensure qb-inventory       # or ox_inventory; required only for safe deposit boxes
ensure codex_banking
```

Grant admin access through QBCore's `admin`/`god` permissions or ACE:

```cfg
add_ace group.admin codex.banking.admin allow
```

## Player controls

- Walk to a bank branch or ATM and press **E**.
- At a branch, deposit or withdraw cash, transfer funds, open savings/shared accounts, issue cards or cheques, create invoices, apply for loans, and rent a safe box.
- At an ATM, select a card and enter its PIN before withdrawing cash or managing an ATM you own.
- `/bank` and `/atm` open the nearest configured location when close enough. `/bankadmin` opens the admin console for authorized users.

## Configuration

Settings are in `config.lua`:

- `Config.Banks` — bank labels, IBAN prefixes, opening fees, withdrawal/ATM fees, and account limits.
- `Config.Branches` — branch coordinates and server-side interaction radii.
- `Config.ATMs.AccessPoints` — allowed ATM coordinates. The client also checks for an ATM model; add coordinates for custom MLOs.
- `Config.Transfer`, `Config.Cards`, `Config.Accounts`, `Config.Savings`, `Config.Loans`, `Config.Invoices`, `Config.Cheques`, and `Config.SafeBoxes` — economy settings.
- `Config.JobAccounts` — QBCore jobs, minimum grades, withdrawal/manage grades, and company-account limits.
- `Config.Locale` is set to `'en'`; the resource ships with an English-only interface.
- `Config.LegacySync.Enabled` — mirror personal balances to QBCore's `bank`. If disabled, existing QBCore bank money is not imported and CodeX works as a separate ledger. In this separate-ledger mode, the first checking account's opening fee is waived when the player has no CodeX checking account, so they can start the ledger; later network accounts use their configured fees.

## Security and integrations

- Card PINs are never returned to the client or stored in plaintext. The database stores a SHA-256 verifier derived using the server secret, Citizen ID, and card ID. Set the secret convar before production use.
- OneSync is recommended for reliable server-side distance checks and vehicle repossession.
- Secured loans expect the standard QBCore `player_vehicles` table with `citizenid` and `plate` columns. On default, `Config.Loans.SeizeVehicleOnDefault` transfers the vehicle to `codex_bank`. Adjust `VehicleTable` and `BankVehicleCitizenId` for a custom schema.
- Company accounts are **CodeX ledger accounts**, not an automatic replacement for `qb-management`. Use the included exports or adapt your job scripts; do not count the same funds in two independent ledgers.
- If you use `qb-inventory`, verify the stash API against your installed version. The `ox_inventory` stash bridge is included.
- With `Config.LegacySync.Enabled = true`, personal checking/savings balances represent the combined QBCore bank balance. Remove other personal banking resources that maintain a separate UI or write to the same bank balance.

## Differences from the reference video

This initial version covers the main banking and economy flows but does not include every feature of the commercial Supreme Banking resource. Missing features include a contact book, recurring transfers, printable monthly statements, sharing safe boxes with multiple players, automatic discovery of every MLO ATM, admin placement tools for branches, and multiple UI layouts. The resource includes 29 configured ATM access points rather than all 104 points shown in the video. Custom branches, ATMs, inventories, and garage integrations need server-specific configuration.

## Verification

Run from the repository root:

```bash
python3 codex_banking/tests/run_checks.py
node --check codex_banking/html/app.js
```

The structural check validates manifest paths, SQL tables/indexes, callbacks, and PIN-verifier storage. The JavaScript command checks NUI syntax. Actual transactions and integration behavior still need to be tested on a FiveM test server with QBCore and oxmysql.

## Resource files

- `config.lua` — settings, locations, and economy.
- `server/` — QBCore bridge, SQL operations, validation, transactions, loans, and administration.
- `client/main.lua` — interaction prompts and NUI integration.
- `html/` — responsive English banking interface.
- `sql/codex_banking.sql` — schema and indexes.
- `install/server.cfg.example` — startup order and secret convar example.
