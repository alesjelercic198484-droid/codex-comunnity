Config = {}

-- Enable extra prints in the server console.
Config.Debug = false

Config.ESX = {
    -- ESX Legacy export is preferred. If your server uses old ESX, set UseExport = false.
    UseExport = true,
    ExportName = 'es_extended',
    SharedObjectEvent = 'esx:getSharedObject'
}

Config.Database = {
    -- auto = oxmysql, mysql-async, or ghmattimysql, in that order.
    Driver = 'auto',
    Table = 'codex_daily_missions',
    AutoCreate = true
}

Config.UI = {
    Title = 'Daily Missions',
    Subtitle = 'Stay online, complete tasks, and claim your rewards.',
    AccentColor = '#26f3c9',
    CommandHelp = 'Open Daily Missions'
}

-- Players open the panel by talking to the mission ped through ox_target.
-- Keep /dailymissions as a fallback command, or set this to false to disable it.
Config.OpenCommand = 'dailymissions'

-- No default keybind. The script intentionally does not register F7 or any other key.
Config.OpenKey = false

Config.Inventory = {
    -- ox_inventory is the primary inventory integration for this version.
    Type = 'ox_inventory',
    AllowESXFallback = true,
    WeaponAsItem = true
}

Config.MissionPed = {
    Enabled = true,
    Model = 'a_m_m_business_01',
    -- Change these coords to the location where you want the daily mission NPC.
    Coords = vector4(215.76, -810.12, 30.73, 340.0),
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    Freeze = true,
    Invincible = true,
    BlockEvents = true,
    Distance = 2.0,
    Target = {
        Label = 'Open Daily Missions',
        Icon = 'fa-solid fa-calendar-check'
    }
}

Config.Reset = {
    -- local = server machine timezone, utc = UTC.
    Timezone = 'local',
    -- Hour when the daily set changes. 0 = midnight.
    Hour = 0
}

Config.Progress = {
    -- all = every unfinished mission counts at the same time.
    -- sequential = only the first unfinished mission counts, then the next one unlocks.
    Mode = 'all',

    TickSeconds = 60,
    SaveIntervalSeconds = 120,
    MaxTickDeltaSeconds = 120,

    -- Optional anti-AFK heartbeat. Keep false for maximum compatibility.
    -- If true, the server only counts players whose client heartbeat is active.
    RequireClientHeartbeat = false,
    HeartbeatTimeoutSeconds = 150
}

Config.Notifications = {
    MissionCompleted = 'Mission completed: %s. Open Daily Missions to claim your reward.',
    Claimed = 'Reward claimed: %s',
    NotReady = 'Your daily mission data is still loading. Try again in a moment.',
    NotCompleted = 'This mission is not completed yet.',
    AlreadyClaimed = 'You already claimed this reward.',
    NoInventorySpace = 'You do not have enough inventory space for this reward.',
    InvalidMission = 'Invalid mission.',
    ClaimBusy = 'Please wait, your previous claim is still processing.'
}

-- Reward types:
-- { type = 'money', amount = 2500, label = '$2,500 Cash' }
-- { type = 'account', account = 'bank', amount = 5000, label = '$5,000 Bank' }
-- { type = 'item', name = 'water', count = 2, label = 'Water x2' }
-- { type = 'weapon', name = 'WEAPON_PISTOL', ammo = 24, label = 'Pistol' }
-- { type = 'command', command = 'giveitem {source} phone 1', label = 'Phone' }
-- { type = 'vehicle', model = 'sultan', label = 'Sultan' } -- requires Config.VehicleRewards.Enabled = true.
Config.Missions = {
    {
        key = 'warmup',
        label = 'Warm Up',
        description = 'Stay online for 10 minutes.',
        requiredSeconds = 10 * 60,
        icon = 'clock',
        rewards = {
            { type = 'money', amount = 2500, label = '$2,500 Cash' }
        }
    },
    {
        key = 'supplies',
        label = 'Daily Supplies',
        description = 'Stay online for 25 minutes.',
        requiredSeconds = 25 * 60,
        icon = 'box',
        rewards = {
            { type = 'item', name = 'burger', count = 1, label = 'Burger x1' },
            { type = 'item', name = 'water', count = 1, label = 'Water x1' }
        }
    },
    {
        key = 'payday',
        label = 'Payday Bonus',
        description = 'Stay online for 45 minutes.',
        requiredSeconds = 45 * 60,
        icon = 'wallet',
        rewards = {
            { type = 'account', account = 'bank', amount = 7500, label = '$7,500 Bank' }
        }
    },
    {
        key = 'loyalty',
        label = 'Loyalty Reward',
        description = 'Stay online for 75 minutes.',
        requiredSeconds = 75 * 60,
        icon = 'star',
        rewards = {
            { type = 'money', amount = 10000, label = '$10,000 Cash' },
            { type = 'item', name = 'water', count = 2, label = 'Water x2' }
        }
    },
    {
        key = 'legend',
        label = 'City Legend',
        description = 'Stay online for 120 minutes.',
        requiredSeconds = 120 * 60,
        icon = 'crown',
        rewards = {
            { type = 'account', account = 'bank', amount = 20000, label = '$20,000 Bank' }
        }
    }
}

Config.Rewards = {
    PreventDuplicateWeapons = true
}

-- Vehicle rewards are disabled by default because owned_vehicles schemas differ between ESX servers.
-- Enable and adjust InsertSQL if you add vehicle rewards to Config.Missions.
Config.VehicleRewards = {
    Enabled = false,
    PlatePrefix = 'DM',
    InsertSQL = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored) VALUES (@owner, @plate, @vehicle, @type, @stored)',
    CheckPlateSQL = 'SELECT plate FROM owned_vehicles WHERE plate = @plate LIMIT 1',
    Type = 'car',
    Stored = 1
}
