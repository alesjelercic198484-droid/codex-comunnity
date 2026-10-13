-- Paste this entry INSIDE the table in ox_inventory/data/items.lua
-- (only when your server runs ox_inventory instead of qb-inventory).
-- Then copy wallet.png into ox_inventory/web/images/.
-- Do not paste a second copy if the item already exists.

['codex_wallet'] = {
    label = 'CodeX Wallet',
    weight = 200,
    stack = false,
    close = true,
    description = 'A premium leather wallet branded CodeX Wallet. Store your ID cards and cash safely inside.',
    client = {
        image = 'wallet.png'
    }
},

-- OPTIONAL: cash item used by the wallet's inventory money mode
-- (Config.Money.Mode = 'item', the default).
-- Only add this if your server does not already have a cash item -
-- if your money item is called differently, change Config.Money.ItemName.

['cash'] = {
    label = 'Cash',
    weight = 0,
    stack = true,
    close = true,
    description = 'Some hard-earned cash.'
},
