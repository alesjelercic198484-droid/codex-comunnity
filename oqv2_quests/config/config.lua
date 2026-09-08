--[[ OQV2 QUESTS — Main configuration | Made with CodeX Dev. ]]

Config = {}

-------------------------------------------------------------------------------
-- GENERAL
-------------------------------------------------------------------------------
Config.Debug            = false        -- verbose console prints
Config.Locale           = 'en'         -- locales/<locale>.json  (en | es)
Config.Framework        = 'esx'        -- only 'esx' is shipped in this build
Config.UseDatabase      = true         -- persist missions/locations/npcs/progress in MySQL
Config.SeedFromConfig   = true         -- on first boot, import config/*.lua entries into the DB

-------------------------------------------------------------------------------
-- ADMIN ACCESS  (who may open the /oqv2 NUI)
-------------------------------------------------------------------------------
Config.Admin = {
    command      = 'oqv2',                         -- the admin panel command
    -- ESX groups allowed to open the panel
    groups       = { 'admin', 'superadmin', 'owner', 'god' },
    -- FiveM ACE permission (add to server.cfg: add_ace group.admin oqv2.admin allow)
    ace          = 'oqv2.admin',
    -- Hard-coded identifiers that always have access (license:xxx / steam:xxx / discord:xxx)
    identifiers  = {
        -- 'license:0000000000000000000000000000000000000000',
    },
    -- console (server id 0) is always allowed
    allowConsole = true,
    logDenied    = true,                           -- print a warning when a non-admin tries /oqv2
}

-------------------------------------------------------------------------------
-- PLAYER JOURNAL  (optional, separate from the admin NUI)
-------------------------------------------------------------------------------
Config.Journal = {
    enabled  = true,
    command  = 'quests',       -- /quests  → player mission journal + discovered map
    keybind  = 'F7',           -- set to false to disable the keybind
}

-------------------------------------------------------------------------------
-- UI / BRANDING
-------------------------------------------------------------------------------
Config.UI = {
    brand        = 'OQV2 QUESTS',
    subtitle     = 'Unlimited Mission System',
    author       = 'Codex Dev: #Alesh48 5654',
    footer       = 'Made with CodeX Dev.',
    accent       = '#e01b84',   -- primary accent (Origen-style magenta)
    accentAlt    = '#7c4dff',   -- secondary accent
    sounds       = true,        -- UI click / open sounds
    blurBackdrop = true,
}

-------------------------------------------------------------------------------
-- PROGRESSION
-------------------------------------------------------------------------------
Config.Progression = {
    enabled      = true,
    maxLevel     = 100,
    baseXP       = 500,      -- XP needed for level 2
    curve        = 1.09,     -- XP(n) = baseXP * curve^(n-1)
    levelUpSound = true,
    -- Rewards handed out automatically every X levels (optional)
    levelRewards = {
        [5]  = { money = 2500 },
        [10] = { money = 7500, items = { { name = 'bandage', count = 5 } } },
        [25] = { money = 25000 },
        [50] = { money = 100000 },
    },
}

-------------------------------------------------------------------------------
-- INTERACTION / WORLD
-------------------------------------------------------------------------------
Config.Interaction = {
    targetDistance   = 2.0,     -- ox_target distance
    spawnDistance    = 120.0,   -- distance at which peds/objects stream in
    despawnDistance  = 150.0,
    tickIdle         = 1200,    -- ms between world checks when far from anything
    tickActive       = 350,     -- ms between world checks when close to a location
    useBlips         = true,
    blipScale        = 0.8,
    discoveryRadius  = 45.0,    -- radius at which an undiscovered location is "found"
    markerFallback   = true,    -- draw a marker if a location has no ped/object
}

-------------------------------------------------------------------------------
-- ECONOMY / INVENTORY
-------------------------------------------------------------------------------
Config.Economy = {
    moneyAccount   = 'money',       -- ESX account used for cash rewards ('money' | 'bank' | 'black_money')
    checkCarry     = true,          -- verify ox_inventory space before granting items
    logTransactions = true,
}

-------------------------------------------------------------------------------
-- EVIL NPC SYSTEM
-------------------------------------------------------------------------------
Config.EvilNPC = {
    enabled          = true,
    maxActiveGroups  = 4,          -- max hostile groups spawned per client at once
    defaultRespawn   = 300,        -- seconds
    dispatchExport   = false,      -- e.g. { resource = 'cd_dispatch', method = 'CustomAlert' }
    policeAlertChance = 65,        -- % chance an "alert police" group actually calls it in
    lootRadius       = 2.0,
    corpseCleanup    = 120,        -- seconds before dead hostiles are removed
}

-------------------------------------------------------------------------------
-- NOTIFICATIONS  (ox_lib by default — swap here for a custom notify resource)
-------------------------------------------------------------------------------
Config.Notify = function(src, data)
    -- data = { title = string, description = string, type = 'success'|'error'|'inform'|'warning', duration = ms }
    if IsDuplicityVersion() then
        TriggerClientEvent('ox_lib:notify', src, data)
    else
        lib.notify(data)
    end
end

-------------------------------------------------------------------------------
-- ANTI-CHEAT / SAFETY
-------------------------------------------------------------------------------
Config.Security = {
    maxDistanceToLocation = 12.0,   -- server rejects turn-ins made further than this from the location
    rateLimitMs           = 750,    -- min ms between two mission events from the same player
    kickOnAbuse           = false,
    abuseThreshold        = 15,     -- flagged events before an admin warning is logged
}

-------------------------------------------------------------------------------
-- DEFAULT COOLDOWN PRESETS (seconds) — referenced by the NUI creator
-------------------------------------------------------------------------------
Config.CooldownPresets = {
    none    = 0,
    hourly  = 3600,
    daily   = 86400,
    weekly  = 604800,
    monthly = 2592000,
}
