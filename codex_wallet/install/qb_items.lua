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
