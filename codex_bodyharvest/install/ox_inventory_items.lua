-- Add these three entries to ox_inventory/data/items.lua
-- (or to your shared item override file).

['finger'] = {
    label = 'Finger',
    weight = 20,
    stack = true,
    close = false,
    description = 'A severed finger. Somebody is missing this.',
},

['ear'] = {
    label = 'Ear',
    weight = 30,
    stack = true,
    close = false,
    description = 'A severed ear. Proof that you were there.',
},

['tongue'] = {
    label = 'Tongue',
    weight = 40,
    stack = true,
    close = false,
    description = 'A cut out tongue. Dead men tell no tales.',
},

-- Optional: a plain (non weapon) knife item, it is already listed in
-- Config.Knives so it unlocks the cutting options as well.
--[[
['knife'] = {
    label = 'Knife',
    weight = 500,
    stack = false,
    close = true,
    description = 'A sharp kitchen knife.',
},
]]
