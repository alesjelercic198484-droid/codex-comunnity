-- Paste this entry INSIDE the table in qb-core/shared/items.lua
-- (or qb-inventory's items file, depending on your server build).
-- Then copy wallet.png into qb-inventory/html/images/.
-- Do not paste a second copy if the item already exists.

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

-- OPTIONAL: cash item used by the wallet's inventory money mode
-- (Config.Money.Mode = 'item', the default).
-- Only add this if your server does not already have a cash item -
-- if your money item is called differently (e.g. 'money'), just change
-- Config.Money.ItemName in the wallet config instead.

['cash'] = {
    name = 'cash',
    label = 'Cash',
    weight = 0,
    type = 'item',
    image = 'cash.png',
    unique = false,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Some hard-earned cash.'
},
