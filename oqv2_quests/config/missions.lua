--[[ OQV2 QUESTS — Default missions (seeded into the DB on first boot)
     You can create/edit everything in-game with /oqv2 — this file is only a starter pack.
     Made with CodeX Dev. ]]

Config.Missions = {

    ---------------------------------------------------------------------------
    -- 1. Simple trade mission — hand over items, get paid (the video example)
    ---------------------------------------------------------------------------
    {
        uid         = 'm_scrap_trade',
        name        = 'Scrap Trade',
        description = 'Old Marco buys used electronics. Bring him 5 pieces of scrap metal and he will pay well — no questions asked.',
        category    = 'general',
        icon        = 'recycle',
        enabled     = true,
        order       = 1,

        requiredLevel = 0,
        xpReward      = 120,
        prerequisites = {},

        objectives = {
            {
                id    = 'obj_scrap_1',
                type  = 'give_item',
                label = 'Hand 5x Scrap Metal to Marco',
                item  = 'scrapmetal',
                count = 5,
            },
        },

        rewards = {
            money = 850,
            items = { { name = 'water', count = 1, chance = 100 } },
        },

        restriction = { type = 'all' },
        cooldown    = { type = 'daily' },

        alert = {
            title       = 'Scrap Trade',
            description = 'Marco is waiting for his scrap metal.',
            sound       = 'quest_start',
        },
    },

    ---------------------------------------------------------------------------
    -- 2. Delivery chain — locked behind mission #1
    ---------------------------------------------------------------------------
    {
        uid         = 'm_night_delivery',
        name        = 'Night Delivery',
        description = 'A sealed package needs to reach the docks before sunrise. Do not open it. Do not ask.',
        category    = 'delivery',
        icon        = 'truck-fast',
        enabled     = true,
        order       = 2,

        requiredLevel = 2,
        xpReward      = 260,
        prerequisites = { 'm_scrap_trade' },

        requirements = { items = {}, money = 0 },

        objectives = {
            {
                id     = 'obj_pickup',
                type   = 'interact',
                label  = 'Pick up the sealed package',
                coords = { x = 707.34, y = -966.71, z = 30.41 },
                radius = 2.0,
                duration = 4000,
                anim   = { dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 },
            },
            {
                id     = 'obj_dropoff',
                type   = 'deliver',
                label  = 'Deliver the package at the docks',
                item   = 'sealed_package',
                count  = 1,
                coords = { x = 1208.61, y = -3115.55, z = 5.54 },
                radius = 3.0,
            },
        },

        rewards = {
            money = 1800,
            items = {},
        },

        restriction = { type = 'all' },
        cooldown    = { type = 'daily' },
        schedule    = { enabled = true, from = 20, to = 6 },

        alert = {
            title       = 'Night Delivery',
            description = 'Get to the docks before sunrise.',
            sound       = 'quest_start',
        },
    },

    ---------------------------------------------------------------------------
    -- 3. Combat mission tied to an Evil NPC group
    ---------------------------------------------------------------------------
    {
        uid         = 'm_clear_the_block',
        name        = 'Clear The Block',
        description = 'A crew took over the alley behind the motel. Deal with them and bring back whatever they were guarding.',
        category    = 'crime',
        icon        = 'crosshairs',
        enabled     = true,
        order       = 3,

        requiredLevel = 5,
        xpReward      = 500,
        prerequisites = { 'm_night_delivery' },

        objectives = {
            {
                id     = 'obj_go_alley',
                type   = 'goto',
                label  = 'Reach the alley behind the motel',
                coords = { x = 328.29, y = -2043.13, z = 21.31 },
                radius = 30.0,
            },
            {
                id     = 'obj_kill',
                type   = 'kill',
                label  = 'Eliminate the crew',
                amount = 3,
                model  = 'g_m_y_ballasout_01',
            },
        },

        rewards = {
            money = 3200,
            black = 1500,
            items = { { name = 'weapon_ammo', count = 30, chance = 60 } },
        },

        restriction = { type = 'level', level = 5 },
        cooldown    = { type = 'weekly' },

        alert = {
            title       = 'Clear The Block',
            description = 'Armed hostiles reported. Be careful.',
            sound       = 'quest_alert',
        },
    },

    ---------------------------------------------------------------------------
    -- 4. Job restricted mission (police example)
    ---------------------------------------------------------------------------
    {
        uid         = 'm_evidence_run',
        name        = 'Evidence Run',
        description = 'Transport the sealed evidence bag from Mission Row to the forensic lab.',
        category    = 'legal',
        icon        = 'shield-halved',
        enabled     = true,
        order       = 4,

        requiredLevel = 0,
        xpReward      = 180,

        objectives = {
            {
                id     = 'obj_evidence',
                type   = 'deliver',
                label  = 'Drop the evidence at the lab',
                item   = 'evidence_bag',
                count  = 1,
                coords = { x = 1855.24, y = 3683.51, z = 34.27 },
                radius = 3.0,
            },
        },

        rewards = { bank = 1200 },
        restriction = { type = 'job', job = 'police', grade = 0 },
        cooldown    = { type = 'hourly' },

        alert = { title = 'Evidence Run', description = 'Chain of custody starts now.', sound = 'quest_start' },
    },
}
