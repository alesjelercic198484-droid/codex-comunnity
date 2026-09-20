--[[
    codex_cryptomining - ox_inventory items
    ---------------------------------------------------------------
    Copy these entries into  ox_inventory/data/items.lua
    (inside the big `return { ... }` table).

    If you rename an item here, rename it in codex_cryptomining/config.lua
    as well (Config.Inventory.Items).
]]

['gpu'] = {
    label = 'Mining GPU',
    weight = 800,
    stack = true,
    close = true,
    description = 'A high end graphics card, the heart of any mining rig.',
    client = {
        image = 'gpu.png'
    }
},

['crypto_cpu'] = {
    label = 'CPU upgrade kit',
    weight = 400,
    stack = true,
    close = true,
    description = 'Boosts the hashrate of a mining rig.',
    client = {
        image = 'crypto_cpu.png'
    }
},

['crypto_cooler'] = {
    label = 'Cooling unit',
    weight = 900,
    stack = true,
    close = true,
    description = 'Reduces wear and the risk of a breakdown.',
    client = {
        image = 'crypto_cooler.png'
    }
},

['crypto_repairkit'] = {
    label = 'Repair kit',
    weight = 500,
    stack = true,
    close = true,
    description = 'Repairs a damaged mining rig.',
    client = {
        image = 'crypto_repairkit.png'
    }
},

['hacking_usb'] = {
    label = 'Hacking USB drive',
    weight = 100,
    stack = true,
    close = true,
    description = 'Bypasses the security system of a warehouse.',
    client = {
        image = 'hacking_usb.png'
    }
},

['hacking_laptop'] = {
    label = 'Hacking laptop',
    weight = 2000,
    stack = false,
    close = true,
    description = 'A laptop loaded with questionable software.',
    client = {
        image = 'hacking_laptop.png'
    }
},
