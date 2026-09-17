# codex_dos_id

ESX resource: a **Department of Defense — Secret Services** ID card item.
Players whose job is `gouv` can use the item to open a UI showing their
**first name, last name and job**, styled like an official ID/badge. When
used, the card is also automatically shown (read-only, no NUI focus) to any
nearby police officers, like handing over an ID in real life.

## Features

- Usable item (`dos_id_card`) restricted to the `gouv` job (configurable, and
  you can allow extra jobs via `Config.AllowedJobs`).
- Clean NUI "ID card" popup with agency name, division, photo placeholder,
  first name, last name, job/position, grade, credential number and barcode.
- Automatically pops the same card (read-only) on screen for nearby players
  with the `police` job when the card is used — simulates "showing your ID to
  the police".
- Fallback `/dosid` command in case your inventory doesn't call
  `ESX.RegisterUsableItem` hooks.
- Compatible with both legacy ESX item system and `ox_inventory` (optional
  `RegisterUsableItem` hook is attempted automatically if `ox_inventory` is
  running).

## Installation

1. Copy the `codex_dos_id` folder into your server `resources` folder.
2. Add the item to your database / inventory:
   - **Legacy ESX (MySQL `items` table):** run `sql/codex_dos_id.sql`.
   - **ox_inventory:** add to `data/items.lua`:
     ```lua
     ['dos_id_card'] = {
         label = 'DoS Secret Services ID',
         weight = 0,
         stack = false,
         close = true,
         description = 'Official Department of Defense - Secret Services credential.'
     },
     ```
3. Make sure a `gouv` job exists (see the SQL file for an example insert), or
   change `Config.Job` in `config.lua` to match your existing government/DoD
   job name.
4. Give the item to a player with the `gouv` job, e.g.:
   ```
   /giveitem dos_id_card 1
   ```
   Or server-side: `xPlayer.addInventoryItem('dos_id_card', 1)`.
5. Add `ensure codex_dos_id` to your `server.cfg`, after `es_extended`.

## Configuration

All options are in `config.lua`:

- `Config.Job` – job required to legitimately hold/use the card (`gouv` by
  default).
- `Config.AllowedJobs` – extra job names allowed to also use the card.
- `Config.Card` – agency name, division name, footer disclaimer text.
- `Config.Presentation.ViewerJobs` – which job(s) automatically see the card
  pop up when it's used nearby (defaults to `police`).
- `Config.Presentation.Radius` – detection radius, in game units, for nearby
  officers.
- `Config.Presentation.AutoCloseMs` – how long the read-only popup stays open
  on the officer's screen.
- `Config.Command` – fallback chat command (`/dosid`) to open your own card
  directly; set to `false` to disable.

## How it works

- Using the item server-side triggers `ESX.RegisterUsableItem('dos_id_card', ...)`.
- The server checks the player's current job against `Config.Job` /
  `Config.AllowedJobs`; if it doesn't match, the player gets a "not
  authorized" notification and nothing opens.
- If authorized, the server builds a small payload (first name, last name,
  job label, grade, a generated credential number) and sends it to the
  client to open the NUI card with full focus (interactive, closable).
- The server also loops over nearby players; anyone with a `police` job
  within `Config.Presentation.Radius` receives the same payload and sees a
  read-only version of the card pop up automatically (no NUI focus stolen,
  auto-closes after `Config.Presentation.AutoCloseMs`).

## Notes

- This resource does not require `ox_target` or `ox_inventory` — it depends
  only on `es_extended`. It will opt-in to `ox_inventory`'s usable item hook
  automatically if that resource is running.
- First/last name are read from the ESX player object (`xPlayer.get('firstName')`
  / `xPlayer.get('lastName')`, with fallbacks for older ESX versions that
  expose `xPlayer.variables` or only `xPlayer.getName()`).
