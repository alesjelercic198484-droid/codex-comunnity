--[[
    codex_policecreator - inventory items

    Add these two entries to ox_inventory/data/items.lua (or the equivalent in
    qb-core/shared/items.lua). Without them the GPS tracker and the evidence
    bag simply cannot be issued - the rest of the resource keeps working.
]]

-- ox_inventory/data/items.lua
return {
    ['codex_tracker'] = {
        label = 'GPS Tracker',
        weight = 250,
        stack = true,
        close = true,
        description = 'A magnetic GPS tracker. Use it next to a vehicle to attach it.'
    },

    ['codex_evidence_bag'] = {
        label = 'Evidence Bag',
        weight = 100,
        stack = true,
        close = true,
        description = 'A numbered evidence bag. Use it at a crime scene to log evidence.'
    }
}

--[[
    QBCore equivalent (qb-core/shared/items.lua):

    codex_tracker = {
        name = 'codex_tracker',
        label = 'GPS Tracker',
        weight = 250,
        type = 'item',
        image = 'codex_tracker.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'A magnetic GPS tracker'
    },

    codex_evidence_bag = {
        name = 'codex_evidence_bag',
        label = 'Evidence Bag',
        weight = 100,
        type = 'item',
        image = 'codex_evidence_bag.png',
        unique = false,
        useable = true,
        shouldClose = true,
        description = 'A numbered evidence bag'
    },
]]
