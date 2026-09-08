--[[ OQV2 QUESTS — Default quest locations (NPC / object / marker givers)
     Made with CodeX Dev. ]]

Config.Locations = {

    {
        uid         = 'loc_marco',
        name        = 'Old Marco',
        description = 'Scrap dealer hanging around the industrial yard.',
        enabled     = true,

        entity = {
            type     = 'ped',
            model    = 'a_m_m_hillbilly_01',
            scenario = 'WORLD_HUMAN_SMOKING',
            freeze   = true,
            invincible = true,
            ignore   = true,
        },

        points = {
            { x = 1088.13, y = -2002.13, z = 30.90, w = 275.0 },
        },
        rotate = { enabled = false, interval = 1800 },

        target = { label = 'Talk to Marco', icon = 'fa-solid fa-comments', distance = 2.0 },

        dialogue = {
            title  = 'Old Marco',
            text   = 'You look like someone who knows where to find metal. Bring me some and we both eat tonight.',
            accept = 'What do you need?',
            decline= 'Not today',
        },

        blip = { enabled = true, sprite = 480, color = 27, scale = 0.8, label = 'Scrap Dealer', shortRange = true },

        missions = { 'm_scrap_trade' },
    },

    {
        uid         = 'loc_dockhand',
        name        = 'Dock Handler',
        description = 'Runs the night shift at the docks.',
        enabled     = true,

        entity = {
            type     = 'ped',
            model    = 's_m_y_dockwork_01',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },

        points = {
            { x = 1204.71, y = -3113.63, z = 5.54, w = 178.0 },
            { x = 856.16,  y = -3140.51, z = 5.90, w = 90.0  },
        },
        rotate = { enabled = true, interval = 1800 },

        target = { label = 'Talk to the handler', icon = 'fa-solid fa-box', distance = 2.0 },

        dialogue = {
            title  = 'Dock Handler',
            text   = 'Packages come, packages go. Keep your mouth shut and there is money in it for you.',
            accept = 'I am listening',
            decline= 'Walk away',
        },

        blip = { enabled = true, sprite = 478, color = 5, scale = 0.8, label = 'Night Deliveries', shortRange = true },

        schedule = { enabled = true, from = 19, to = 7 },

        missions = { 'm_night_delivery' },
    },

    {
        uid         = 'loc_informant',
        name        = 'Street Informant',
        description = 'Sells information about the crew holding the block.',
        enabled     = true,

        entity = {
            type  = 'ped',
            model = 'a_m_y_soucent_01',
            anim  = { dict = 'amb@world_human_bum_standing@twitchy@idle_a', clip = 'idle_a' },
        },

        points = {
            { x = 336.27, y = -2027.15, z = 21.44, w = 320.0 },
        },

        target = { label = 'Talk to the informant', icon = 'fa-solid fa-user-secret', distance = 2.0 },

        dialogue = {
            title  = 'Street Informant',
            text   = 'They are back in the alley, four of them, packing. You handle it, I point you to the stash.',
            accept = 'Where are they?',
            decline= 'Later',
        },

        blip = { enabled = false, sprite = 480, color = 1, scale = 0.7 },

        missions = { 'm_clear_the_block' },
    },

    {
        uid         = 'loc_evidence_locker',
        name        = 'Evidence Locker',
        description = 'Mission Row evidence intake.',
        enabled     = true,

        entity = {
            type  = 'object',
            model = 'prop_box_wood04a',
        },

        points = {
            { x = 473.61, y = -996.14, z = 25.06, w = 0.0 },
        },

        target = { label = 'Open the evidence locker', icon = 'fa-solid fa-box-archive', distance = 1.5 },

        dialogue = {
            title  = 'Evidence Locker',
            text   = 'A sealed bag is tagged and ready for transport to the forensic lab.',
            accept = 'Take the bag',
            decline= 'Close',
        },

        blip = { enabled = false },

        missions = { 'm_evidence_run' },
    },
}
