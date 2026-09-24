--[[
    codex_bodyharvest - configuration
    ---------------------------------------------------------------------
    Every gameplay value lives here. The server never trusts the client,
    so a value changed here changes it for everybody.

    Coordinates marked with "-- EDIT" are the ones you will most likely
    want to move so they fit your own map / MLO setup.
]]

Config = {}

-- Prints extra information in the server and client console.
Config.Debug = false

Config.ESX = {
    UseExport = true,
    ExportName = 'es_extended',
    SharedObjectEvent = 'esx:getSharedObject'
}

-- ---------------------------------------------------------------------------
-- STATE BAG KEYS
-- The victim replicates "I am dead" and the server replicates "these parts are
-- already gone", so ox_target can decide instantly without a callback.
-- ---------------------------------------------------------------------------
Config.StateKeys = {
    Dead = 'codexHarvestDead',
    Death = 'codexHarvestDeathId',
    Parts = 'codexHarvestParts'
}

-- ---------------------------------------------------------------------------
-- HARVESTING
-- ---------------------------------------------------------------------------
Config.Harvest = {
    -- ox_target interaction distance on a dead player.
    TargetDistance = 1.8,
    -- The server refuses anything further away than this (anti cheat).
    ServerDistance = 3.0,
    -- Allow cutting parts off your own (dead) body. Keep this false.
    AllowSelf = false,
    -- A knife (see Config.Knives) must be in the inventory.
    RequireKnife = true,
    -- The harvester must be alive himself.
    RequireAlive = true,
    -- Extra server side validation: a player above this health is "alive" and
    -- can never be harvested, even if his client claims to be dead.
    -- Raise it (for example 150) if your ambulance job uses a "last stand"
    -- state where the ped keeps health while being down.
    ServerHealthCheck = true,
    DeadHealthThreshold = 100,
    -- A revived / respawned player can be harvested again.
    ResetOnRespawn = true,
    -- Seconds a player has to wait between two cuts.
    Cooldown = 3,
    -- How often (ms) the client refreshes its own death state bag.
    DeathCheckInterval = 750,
    -- A finish packet that arrives faster than duration * this factor is
    -- rejected (protects against instant-finish cheats).
    MinDurationFactor = 0.85,
    -- Seconds before an unfinished (crashed / stuck) cut is released again.
    PendingTimeout = 60
}

-- Any of these items in the inventory unlocks the interaction.
-- ox_inventory stores weapons as items, so the weapon names work directly.
Config.Knives = {
    'WEAPON_KNIFE',
    'WEAPON_DAGGER',
    'WEAPON_SWITCHBLADE',
    'WEAPON_MACHETE',
    'WEAPON_BATTLEAXE',
    'WEAPON_HATCHET',
    'WEAPON_STONE_HATCHET',
    'WEAPON_KNIFE_2',
    'knife' -- plain (non weapon) knife item, if your server has one
}

-- One of each part per dead body. Add your own parts here if you want more.
Config.Parts = {
    {
        id = 'finger',
        item = 'finger',
        label = 'Cut the finger',
        noun = 'a finger',
        icon = 'fa-solid fa-hand-scissors',
        progress = 'Cutting off a finger...',
        duration = 6000,
        anim = { dict = 'anim@gangops@facility@servers@bodysearch', clip = 'player_search', flag = 49 },
        prop = { model = 'prop_knife', bone = 57005, pos = vec3(0.09, 0.03, 0.02), rot = vec3(-78.0, 13.0, 28.0) }
    },
    {
        id = 'ear',
        item = 'ear',
        label = 'Cut the ear',
        noun = 'an ear',
        icon = 'fa-solid fa-ear-listen',
        progress = 'Cutting off an ear...',
        duration = 7000,
        anim = { dict = 'anim@gangops@facility@servers@bodysearch', clip = 'player_search', flag = 49 },
        prop = { model = 'prop_knife', bone = 57005, pos = vec3(0.09, 0.03, 0.02), rot = vec3(-78.0, 13.0, 28.0) }
    },
    {
        id = 'tongue',
        item = 'tongue',
        label = 'Cut the tongue',
        noun = 'the tongue',
        icon = 'fa-solid fa-comment-slash',
        progress = 'Cutting out the tongue...',
        duration = 9000,
        anim = { dict = 'anim@gangops@facility@servers@bodysearch', clip = 'player_search', flag = 49 },
        prop = { model = 'prop_knife', bone = 57005, pos = vec3(0.09, 0.03, 0.02), rot = vec3(-78.0, 13.0, 28.0) }
    }
}

-- ---------------------------------------------------------------------------
-- HIDDEN DEALER (illegal buyer)
-- ---------------------------------------------------------------------------
Config.Dealer = {
    Enabled = true,
    -- EDIT: abandoned mine shaft in the Great Chaparral - far away from any job.
    Coords = vec4(-595.19, 2091.56, 131.41, 105.0),
    Model = 's_m_y_dealer_01',
    Scenario = 'WORLD_HUMAN_SMOKING',
    -- ox_target distance for the dealer.
    Distance = 2.0,
    -- The server refuses a sale from further away than this.
    ServerDistance = 5.0,
    -- ESX account that receives the money: 'black_money' (dirty cash), 'money' or 'bank'.
    Account = 'black_money',
    -- true  = the dealer buys the whole stack at once (minimum still applies)
    -- false = the dealer buys exactly the minimum amount per sale
    SellAll = true,
    -- Seconds between two sales of the same player.
    Cooldown = 5,
    -- Spoken dialogue when approached by a player.
    Dialogue = {
        Enabled = true,
        Text = 'What can i do for you today my boy',
        AudioFile = 'dealer_greeting.mp3',
        Distance = 4.0,       -- distance from dealer to trigger speech
        Cooldown = 15,        -- seconds between greetings per player
        Volume = 0.6,
        Subtitles = true,     -- display subtitle notification
        NativeSpeech = true   -- trigger GTA V ped speech native as well
    },
    -- The location is supposed to be secret, so no blip by default.
    Blip = {
        Enabled = false,
        Sprite = 496,
        Colour = 40,
        Scale = 0.7,
        Label = 'Collector'
    },
    Deals = {
        { item = 'finger', name = 'fingers', label = 'Sell fingers', icon = 'fa-solid fa-hand-scissors', min = 3, price = 30000 },
        { item = 'ear',    name = 'ears',    label = 'Sell ears',    icon = 'fa-solid fa-ear-listen',    min = 3, price = 40000 },
        { item = 'tongue', name = 'tongues', label = 'Sell tongues', icon = 'fa-solid fa-comment-slash', min = 3, price = 35000 }
    }
}

-- ---------------------------------------------------------------------------
-- POLICE ALERT (fired the moment somebody cuts a body part)
-- ---------------------------------------------------------------------------
Config.Alert = {
    Enabled = true,
    -- Every job in this list receives the alert.
    Jobs = { 'police', 'sheriff', 'state', 'bcso', 'fib' },
    -- Seconds between two alerts caused by the same player (0 = every cut alerts).
    Cooldown = 0,
    -- The reported position is randomised by up to this many meters (0 = exact).
    Jitter = 0.0,
    Blip = {
        -- Seconds the flashing red blip stays on the map.
        Duration = 90,
        Sprite = 458,
        Colour = 1,
        Scale = 1.2,
        Alpha = 255,
        FlashInterval = 500,
        -- Native blip flashing (recommended for point blips).
        Flash = true,
        -- Extra alpha blinking on top of it. Only enable it when your blip
        -- category ignores SetBlipFlashes, otherwise both effects fight.
        AlphaFlash = false,
        Label = 'Assassination In Progress',
        -- Plays a short dispatch sound for the officers.
        Sound = true,
        SoundName = 'Lose_1st',
        SoundSet = 'GTAO_FM_Events_Soundset'
    }
}

-- ---------------------------------------------------------------------------
-- OPEN FIRE ZONE (public warning, sent after the police alert)
-- ---------------------------------------------------------------------------
Config.OpenFireZone = {
    Enabled = true,
    -- Seconds between the police alert and the public announcement.
    Delay = 20,
    -- Seconds the flashing red circle stays on the map.
    Duration = 90,
    Radius = 120.0,
    Colour = 1,
    Alpha = 128,
    -- Radius blips ignore SetBlipFlashes, so the alpha is blinked instead.
    FlashInterval = 500,
    -- The player who did the cutting does not get the public warning.
    ExcludeHarvester = true,
    -- Police also get the public announcement (they already got the alert).
    ExcludePolice = false
}

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------------
Config.Notify = {
    UseOxLib = true,          -- lib.notify, falls back to ESX.ShowNotification
    Duration = 7000,
    Position = 'top',
    Title = 'Body Harvest'
}

-- ---------------------------------------------------------------------------
-- LOGS
-- ---------------------------------------------------------------------------
Config.Logs = {
    Console = true,
    -- Optional Discord webhook, leave empty to disable.
    Webhook = '',
    WebhookName = 'codex_bodyharvest'
}

-- ---------------------------------------------------------------------------
-- TEXT (everything the player can read)
-- ---------------------------------------------------------------------------
Config.Text = {
    NoKnife            = 'You need a knife for that.',
    NotDead            = 'This person is not dead.',
    TooFar             = 'You are too far away.',
    AlreadyTaken       = 'Somebody already took that part.',
    Busy               = 'You are already cutting.',
    InProgress         = 'Somebody else is cutting that part right now.',
    Cooldown           = 'Your hands are still shaking, wait a moment.',
    Cancelled          = 'You stopped cutting.',
    NoSpace            = 'You cannot carry that.',
    InvalidTarget      = 'Invalid target.',
    DeadHarvester      = 'You cannot do that while you are down.',
    HarvestSuccess     = 'You cut off %s and put it in your bag.',

    SellNotEnough      = 'The collector wants at least %s %s.',
    SellSuccess        = 'Sold %sx %s for $%s.',
    SellFailed         = 'The deal did not go through.',
    SellCooldown       = 'The collector is still counting, wait a moment.',

    PoliceAlertTitle   = 'Assassination In Progress',
    PoliceAlertBody    = 'Body mutilation reported. Suspect is armed with a blade.',
    ZoneTitle          = 'Police Announcement',
    ZoneBody           = 'This Area is OPEN FIRE ZONE Stay Away!'
}

-- ---------------------------------------------------------------------------
-- SHARED HELPER
-- ---------------------------------------------------------------------------
--- 120000 -> "120,000" (used by the client labels and the server messages).
function Config.FormatMoney(amount)
    local formatted = tostring(math.floor(tonumber(amount) or 0))

    while true do
        local replaced
        formatted, replaced = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2')

        if replaced == 0 then
            break
        end
    end

    return formatted
end
