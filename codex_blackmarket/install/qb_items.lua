-- Optional QBCore item definitions.
-- Check qb-core/shared/items.lua first and paste ONLY entries that are missing
-- into the QBShared.Items table. Do not add duplicates.
--
-- The resource safely hides any catalog/sale item that QBCore has not
-- registered, so you can also simply remove entries from config.lua.

['advancedlockpick'] = {
    name = 'advancedlockpick', label = 'Advanced Lockpick', weight = 500,
    type = 'item', image = 'advancedlockpick.png', unique = false,
    useable = false, shouldClose = true, description = 'A reinforced lockpick.'
},
['electronickit'] = {
    name = 'electronickit', label = 'Electronic Kit', weight = 1000,
    type = 'item', image = 'electronickit.png', unique = false,
    useable = false, shouldClose = true, description = 'A kit for electronic work.'
},
['trojan_usb'] = {
    name = 'trojan_usb', label = 'Encrypted USB', weight = 100,
    type = 'item', image = 'trojan_usb.png', unique = false,
    useable = false, shouldClose = true, description = 'An encrypted storage device.'
},
['thermite'] = {
    name = 'thermite', label = 'Thermite Charge', weight = 1000,
    type = 'item', image = 'thermite.png', unique = false,
    useable = false, shouldClose = true, description = 'A dangerous incendiary compound.'
},
['pistol_ammo'] = {
    name = 'pistol_ammo', label = 'Pistol Ammunition', weight = 200,
    type = 'item', image = 'pistol_ammo.png', unique = false,
    useable = false, shouldClose = true, description = 'A box of pistol ammunition.'
},
['smg_ammo'] = {
    name = 'smg_ammo', label = 'SMG Ammunition', weight = 250,
    type = 'item', image = 'smg_ammo.png', unique = false,
    useable = false, shouldClose = true, description = 'A box of SMG ammunition.'
},
['shotgun_ammo'] = {
    name = 'shotgun_ammo', label = 'Shotgun Shells', weight = 300,
    type = 'item', image = 'shotgun_ammo.png', unique = false,
    useable = false, shouldClose = true, description = 'A box of shotgun shells.'
},
['cryptostick'] = {
    name = 'cryptostick', label = 'Encrypted Data Stick', weight = 100,
    type = 'item', image = 'cryptostick.png', unique = false,
    useable = false, shouldClose = true, description = 'A recovered encrypted data stick.'
},
['weed_brick'] = {
    name = 'weed_brick', label = 'Compressed Package', weight = 1000,
    type = 'item', image = 'weed_brick.png', unique = false,
    useable = false, shouldClose = true, description = 'A wrapped bulk package.'
},
['cokebaggy'] = {
    name = 'cokebaggy', label = 'Powder Packet', weight = 100,
    type = 'item', image = 'cokebaggy.png', unique = false,
    useable = false, shouldClose = true, description = 'A sealed packet.'
},
['meth'] = {
    name = 'meth', label = 'Crystal Package', weight = 100,
    type = 'item', image = 'meth.png', unique = false,
    useable = false, shouldClose = true, description = 'A small sealed package.'
}
