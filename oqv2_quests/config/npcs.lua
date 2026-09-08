--[[ OQV2 QUESTS — Default "Evil NPC" hostile groups
     Made with CodeX Dev. ]]

Config.EvilNpcs = {

    {
        uid         = 'npc_block_crew',
        name        = 'Block Crew',
        enabled     = true,
        model       = 'g_m_y_ballasout_01',
        count       = 3,
        companions  = 1,
        weapons     = { 'WEAPON_PISTOL', 'WEAPON_MICROSMG' },
        coords      = { x = 328.29, y = -2043.13, z = 21.31 },
        radius      = 18.0,
        trigger     = { type = 'proximity', distance = 80.0 },
        difficulty  = 'normal',
        aggression  = 80,
        alertPolice = true,
        respawn     = 600,
        loot        = {
            { name = 'weapon_ammo', count = 15, chance = 55 },
            { name = 'bandage',     count = 2,  chance = 35 },
        },
        money         = { min = 150, max = 600 },
        xp            = 40,
        linkedMission = 'm_clear_the_block',
    },

    {
        uid         = 'npc_desert_smugglers',
        name        = 'Desert Smugglers',
        enabled     = false,        -- enable in-game via /oqv2 when you want it live
        model       = 'g_m_m_mexboss_01',
        count       = 4,
        companions  = 2,
        weapons     = { 'WEAPON_ASSAULTRIFLE' },
        coords      = { x = 1387.24, y = 3608.05, z = 34.98 },
        radius      = 30.0,
        trigger     = { type = 'proximity', distance = 120.0 },
        difficulty  = 'hard',
        aggression  = 95,
        alertPolice = true,
        respawn     = 900,
        loot        = {
            { name = 'weapon_ammo', count = 30, chance = 70 },
        },
        money = { min = 400, max = 1500 },
        xp    = 90,
    },
}
