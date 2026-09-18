Config = {}

Config.Debug = false

Config.ESX = {
    UseExport = true,
    ExportName = 'es_extended',
    SharedObjectEvent = 'esx:getSharedObject'
}

-- The SQL file creates these six grades.  Every grade can use the government tools;
-- grade 4 and 5 are still useful for roleplay permissions in your other resources.
Config.Job = {
    Name = 'gouv',
    Label = 'Government of San Andreas',
    MinimumGrade = 0,
    MaximumGrade = 5,
    Grades = {
        [0] = { name = 'judge', label = 'Judge' },
        [1] = { name = 'prosecutor', label = 'Prosecutor' },
        [2] = { name = 'governor', label = 'Governor' },
        [3] = { name = 'president', label = 'President' },
        [4] = { name = 'secret_service', label = 'Secret Services' },
        [5] = { name = 'us_marshal', label = 'US Marshal' }
    }
}

-- These are deliberately configurable.  Add your server's sheriff/FIB job names here
-- if they should receive the same protected-police behaviour.
Config.PoliceJobs = {
    police = true,
    sheriff = true,
    state = true,
    highway = true,
    fib = true,
    bcso = true,
    lspd = true,
    saspr = true
}

Config.AmbulanceJobs = {
    ambulance = true,
    ems = true,
    doctor = true,
    fire = true
}

Config.Commands = {
    Satellite = 'sattelite', -- kept exactly as requested
    MDT = 'gouvmdt',
    Armory = 'gouvarsenal'
}

Config.UI = {
    Title = 'GOUV // COMMAND TABLET',
    Subtitle = 'Government operations, justice records and live city intelligence.',
    Accent = '#80f7bc',
    RefreshMilliseconds = 2500
}

-- The resource uses ox_target rather than a keybind for physical access points.
-- Move these two peds to your courthouse/government building.
Config.Locations = {
    MDT = {
        Enabled = true,
        Model = 's_m_m_highsec_01',
        Coords = vector4(-545.14, -204.45, 38.22, 211.0),
        Scenario = 'WORLD_HUMAN_STAND_MOBILE',
        Label = 'Open Government MDT',
        Icon = 'fa-solid fa-tablet-screen-button'
    },
    Armory = {
        Enabled = true,
        Model = 's_m_y_armymech_01',
        Coords = vector4(-548.72, -201.48, 38.22, 28.0),
        Scenario = 'WORLD_HUMAN_GUARD_STAND',
        Label = 'Open Government Arsenal',
        Icon = 'fa-solid fa-shield-halved'
    }
}

Config.Target = {
    Distance = 2.2,
    PlayerDistance = 2.4
}

Config.Cuffs = {
    -- false means a cuff remains until a gouv member uses Remove Cuffs.
    AutoReleaseSeconds = false,
    SoftLabel = 'Soft Cuff',
    HardLabel = 'Hard Cuff'
}

Config.Fines = {
    Account = 'bank',
    Minimum = 1,
    Maximum = 500000,
    RequireFunds = true
}

Config.Security = {
    -- This is an interaction safeguard, not a way to bypass ox_inventory hooks.
    MaxInteractionDistance = 8.0,
    UnauthorizedTazeRadius = 10.0,
    TazeCooldownSeconds = 4,
    RestraintCheckMilliseconds = 250,
    PositionUpdateMilliseconds = 2000,
    NotifyPolice = true
}

Config.Satellite = {
    -- Los Santos / Blaine County world bounds.  Adjust if your map is custom.
    MapBounds = {
        minX = -4000.0,
        maxX = 4500.0,
        minY = -5000.0,
        maxY = 8500.0
    },
    ShowNames = true,
    ShowCoordinates = true
}

-- A native police MDT is different on every server.  The built-in GOUV MDT is always
-- available.  If your police resource exposes a client event/export, configure it here
-- and the bridge button in the tablet will invoke it for gouv members.
Config.MDT = {
    Bridge = {
        Enabled = false,
        Resource = 'your_police_mdt',
        Export = false,
        ExportName = 'openMDT',
        ClientEvent = 'police_mdt:client:open'
    }
}

Config.Armory = {
    Enabled = true,
    MaxItemCount = 50,
    WeaponAmmo = 250,
    -- Item names are sent to ox_inventory.  Items not installed on the server simply
    -- return a clean error; no arbitrary item name can be requested by a client.
    Items = {
        { name = 'handcuffs', label = 'Handcuffs', count = 1, icon = '🔗' },
        { name = 'cuffkeys', label = 'Cuff Keys', count = 1, icon = '🗝️' },
        { name = 'radio', label = 'Police Radio', count = 1, icon = '📻' },
        { name = 'bodycam', label = 'Body Camera', count = 1, icon = '📹' },
        { name = 'police_stormram', label = 'Police Storm Ram', count = 1, icon = '🚪' },
        { name = 'evidence_bag', label = 'Evidence Bag', count = 5, icon = '🧾' },
        { name = 'fingerprint_kit', label = 'Fingerprint Kit', count = 1, icon = '🧪' },
        { name = 'breathalyzer', label = 'Breathalyzer', count = 1, icon = '🫁' },
        { name = 'repairkit', label = 'Repair Kit', count = 1, icon = '🛠️' },
        { name = 'medikit', label = 'First Aid Kit', count = 2, icon = '➕' },
        { name = 'armour', label = 'Body Armour', count = 1, icon = '🛡️' },
        { name = 'police_badge', label = 'Government Badge', count = 1, icon = '🎖️' },
        { name = 'spikestrip', label = 'Spike Strip', count = 2, icon = '⛓️' },
        { name = 'evidence', label = 'Evidence Item', count = 5, icon = '🔬' },
        { name = 'police_shield', label = 'Police Shield', count = 1, icon = '🛡️' },
        { name = 'megaphone', label = 'Megaphone', count = 1, icon = '📣' }
    },
    -- ox_inventory weapon item names.  This covers the standard GTA V arsenal;
    -- remove any DLC item your installed ox_inventory build does not define.
    Weapons = {
        { name = 'WEAPON_KNIFE', label = 'Knife', icon = '🔪' },
        { name = 'WEAPON_NIGHTSTICK', label = 'Nightstick', icon = '🦯' },
        { name = 'WEAPON_HAMMER', label = 'Hammer', icon = '🔨' },
        { name = 'WEAPON_BAT', label = 'Baseball Bat', icon = '🏏' },
        { name = 'WEAPON_CROWBAR', label = 'Crowbar', icon = '🔧' },
        { name = 'WEAPON_GOLFCLUB', label = 'Golf Club', icon = '🏌️' },
        { name = 'WEAPON_BOTTLE', label = 'Bottle', icon = '🍾' },
        { name = 'WEAPON_DAGGER', label = 'Antique Cavalry Dagger', icon = '🗡️' },
        { name = 'WEAPON_HATCHET', label = 'Hatchet', icon = '🪓' },
        { name = 'WEAPON_KNUCKLE', label = 'Knuckle Duster', icon = '🥊' },
        { name = 'WEAPON_MACHETE', label = 'Machete', icon = '🗡️' },
        { name = 'WEAPON_FLASHLIGHT', label = 'Flashlight', icon = '🔦' },
        { name = 'WEAPON_SWITCHBLADE', label = 'Switchblade', icon = '🗡️' },
        { name = 'WEAPON_POOLCUE', label = 'Pool Cue', icon = '🎱' },
        { name = 'WEAPON_WRENCH', label = 'Wrench', icon = '🔩' },
        { name = 'WEAPON_BATTLEAXE', label = 'Battle Axe', icon = '🪓' },
        { name = 'WEAPON_STONE_HATCHET', label = 'Stone Hatchet', icon = '🪓' },
        { name = 'WEAPON_PISTOL', label = 'Pistol', icon = '🔫' },
        { name = 'WEAPON_PISTOL_MK2', label = 'Pistol Mk II', icon = '🔫' },
        { name = 'WEAPON_COMBATPISTOL', label = 'Combat Pistol', icon = '🔫' },
        { name = 'WEAPON_APPISTOL', label = 'AP Pistol', icon = '🔫' },
        { name = 'WEAPON_STUNGUN', label = 'Stun Gun', icon = '⚡' },
        { name = 'WEAPON_PISTOL50', label = 'Pistol .50', icon = '🔫' },
        { name = 'WEAPON_SNSPISTOL', label = 'SNS Pistol', icon = '🔫' },
        { name = 'WEAPON_SNSPISTOL_MK2', label = 'SNS Pistol Mk II', icon = '🔫' },
        { name = 'WEAPON_HEAVYPISTOL', label = 'Heavy Pistol', icon = '🔫' },
        { name = 'WEAPON_VINTAGEPISTOL', label = 'Vintage Pistol', icon = '🔫' },
        { name = 'WEAPON_FLAREGUN', label = 'Flare Gun', icon = '🚨' },
        { name = 'WEAPON_MARKSMANPISTOL', label = 'Marksman Pistol', icon = '🔫' },
        { name = 'WEAPON_REVOLVER', label = 'Heavy Revolver', icon = '🔫' },
        { name = 'WEAPON_REVOLVER_MK2', label = 'Heavy Revolver Mk II', icon = '🔫' },
        { name = 'WEAPON_DOUBLEACTION', label = 'Double Action Revolver', icon = '🔫' },
        { name = 'WEAPON_RAYPISTOL', label = 'Up-n-Atomizer', icon = '🛸' },
        { name = 'WEAPON_CERAMICPISTOL', label = 'Ceramic Pistol', icon = '🔫' },
        { name = 'WEAPON_NAVYREVOLVER', label = 'Navy Revolver', icon = '🔫' },
        { name = 'WEAPON_GADGETPISTOL', label = 'Perico Pistol', icon = '🔫' },
        { name = 'WEAPON_PISTOLXM3', label = 'WM 29 Pistol', icon = '🔫' },
        { name = 'WEAPON_MICROSMG', label = 'Micro SMG', icon = '🔫' },
        { name = 'WEAPON_SMG', label = 'SMG', icon = '🔫' },
        { name = 'WEAPON_SMG_MK2', label = 'SMG Mk II', icon = '🔫' },
        { name = 'WEAPON_ASSAULTSMG', label = 'Assault SMG', icon = '🔫' },
        { name = 'WEAPON_COMBATPDW', label = 'Combat PDW', icon = '🔫' },
        { name = 'WEAPON_MACHINEPISTOL', label = 'Machine Pistol', icon = '🔫' },
        { name = 'WEAPON_MINISMG', label = 'Mini SMG', icon = '🔫' },
        { name = 'WEAPON_RAYCARBINE', label = 'Unholy Hellbringer', icon = '🛸' },
        { name = 'WEAPON_TECPISTOL', label = 'Tactical SMG', icon = '🔫' },
        { name = 'WEAPON_ASSAULTRIFLE', label = 'Assault Rifle', icon = '🔫' },
        { name = 'WEAPON_ASSAULTRIFLE_MK2', label = 'Assault Rifle Mk II', icon = '🔫' },
        { name = 'WEAPON_CARBINERIFLE', label = 'Carbine Rifle', icon = '🔫' },
        { name = 'WEAPON_CARBINERIFLE_MK2', label = 'Carbine Rifle Mk II', icon = '🔫' },
        { name = 'WEAPON_ADVANCEDRIFLE', label = 'Advanced Rifle', icon = '🔫' },
        { name = 'WEAPON_SPECIALCARBINE', label = 'Special Carbine', icon = '🔫' },
        { name = 'WEAPON_SPECIALCARBINE_MK2', label = 'Special Carbine Mk II', icon = '🔫' },
        { name = 'WEAPON_BULLPUPRIFLE', label = 'Bullpup Rifle', icon = '🔫' },
        { name = 'WEAPON_BULLPUPRIFLE_MK2', label = 'Bullpup Rifle Mk II', icon = '🔫' },
        { name = 'WEAPON_COMPACTRIFLE', label = 'Compact Rifle', icon = '🔫' },
        { name = 'WEAPON_MILITARYRIFLE', label = 'Military Rifle', icon = '🔫' },
        { name = 'WEAPON_HEAVYRIFLE', label = 'Heavy Rifle', icon = '🔫' },
        { name = 'WEAPON_TACTICALRIFLE', label = 'Service Carbine', icon = '🔫' },
        { name = 'WEAPON_MG', label = 'MG', icon = '🔫' },
        { name = 'WEAPON_COMBATMG', label = 'Combat MG', icon = '🔫' },
        { name = 'WEAPON_COMBATMG_MK2', label = 'Combat MG Mk II', icon = '🔫' },
        { name = 'WEAPON_GUSENBERG', label = 'Gusenberg Sweeper', icon = '🔫' },
        { name = 'WEAPON_HOMINGLAUNCHER', label = 'Homing Launcher', icon = '🚀' },
        { name = 'WEAPON_PUMPSHOTGUN', label = 'Pump Shotgun', icon = '🔫' },
        { name = 'WEAPON_PUMPSHOTGUN_MK2', label = 'Pump Shotgun Mk II', icon = '🔫' },
        { name = 'WEAPON_SAWNOFFSHOTGUN', label = 'Sawed-Off Shotgun', icon = '🔫' },
        { name = 'WEAPON_ASSAULTSHOTGUN', label = 'Assault Shotgun', icon = '🔫' },
        { name = 'WEAPON_BULLPUPSHOTGUN', label = 'Bullpup Shotgun', icon = '🔫' },
        { name = 'WEAPON_MUSKET', label = 'Musket', icon = '🔫' },
        { name = 'WEAPON_HEAVYSHOTGUN', label = 'Heavy Shotgun', icon = '🔫' },
        { name = 'WEAPON_DBSHOTGUN', label = 'Double Barrel Shotgun', icon = '🔫' },
        { name = 'WEAPON_AUTOSHOTGUN', label = 'Sweeper Shotgun', icon = '🔫' },
        { name = 'WEAPON_COMBATSHOTGUN', label = 'Combat Shotgun', icon = '🔫' },
        { name = 'WEAPON_SNIPERRIFLE', label = 'Sniper Rifle', icon = '🎯' },
        { name = 'WEAPON_HEAVYSNIPER', label = 'Heavy Sniper', icon = '🎯' },
        { name = 'WEAPON_HEAVYSNIPER_MK2', label = 'Heavy Sniper Mk II', icon = '🎯' },
        { name = 'WEAPON_MARKSMANRIFLE', label = 'Marksman Rifle', icon = '🎯' },
        { name = 'WEAPON_MARKSMANRIFLE_MK2', label = 'Marksman Rifle Mk II', icon = '🎯' },
        { name = 'WEAPON_PRECISIONRIFLE', label = 'Precision Rifle', icon = '🎯' },
        { name = 'WEAPON_GRENADELAUNCHER', label = 'Grenade Launcher', icon = '💥' },
        { name = 'WEAPON_GRENADELAUNCHER_SMOKE', label = 'Smoke Grenade Launcher', icon = '💨' },
        { name = 'WEAPON_RPG', label = 'RPG', icon = '🚀' },
        { name = 'WEAPON_MINIGUN', label = 'Minigun', icon = '💥' },
        { name = 'WEAPON_FIREWORK', label = 'Firework Launcher', icon = '🎆' },
        { name = 'WEAPON_RAILGUN', label = 'Railgun', icon = '⚡' },
        { name = 'WEAPON_RAILGUNXM3', label = 'Railgun XM3', icon = '⚡' },
        { name = 'WEAPON_COMPACTLAUNCHER', label = 'Compact Grenade Launcher', icon = '💥' },
        { name = 'WEAPON_RAYMINIGUN', label = 'Widowmaker', icon = '🛸' },
        { name = 'WEAPON_GRENADE', label = 'Grenade', icon = '💣' },
        { name = 'WEAPON_BZGAS', label = 'BZ Gas', icon = '💨' },
        { name = 'WEAPON_MOLOTOV', label = 'Molotov', icon = '🔥' },
        { name = 'WEAPON_STICKYBOMB', label = 'Sticky Bomb', icon = '💣' },
        { name = 'WEAPON_PROXMINE', label = 'Proximity Mine', icon = '💣' },
        { name = 'WEAPON_SNOWBALL', label = 'Snowball', icon = '❄️' },
        { name = 'WEAPON_SNOWLAUNCHER', label = 'Snowball Launcher', icon = '❄️' },
        { name = 'WEAPON_PIPEBOMB', label = 'Pipe Bomb', icon = '💣' },
        { name = 'WEAPON_ACIDPACKAGE', label = 'Acid Package', icon = '☣️' },
        { name = 'WEAPON_DIGISCANNER', label = 'Digi Scanner', icon = '📡' },
        { name = 'WEAPON_METALDETECTOR', label = 'Metal Detector', icon = '📡' },
        { name = 'WEAPON_RUBBERGUN', label = 'Rubber Gun', icon = '🔫' },
        { name = 'WEAPON_STUNGUN_MP', label = 'Stun Gun MP', icon = '⚡' },
        { name = 'WEAPON_BALL', label = 'Ball', icon = '⚾' },
        { name = 'WEAPON_SMOKEGRENADE', label = 'Tear Gas', icon = '💨' },
        { name = 'WEAPON_FLARE', label = 'Flare', icon = '🚨' },
        { name = 'WEAPON_PETROLCAN', label = 'Jerry Can', icon = '⛽' },
        { name = 'WEAPON_FIREEXTINGUISHER', label = 'Fire Extinguisher', icon = '🧯' },
        { name = 'WEAPON_HAZARDCAN', label = 'Hazardous Jerry Can', icon = '☣️' },
        { name = 'WEAPON_FERTILIZERCAN', label = 'Fertilizer Can', icon = '🧪' },
        { name = 'WEAPON_BATON', label = 'Baton', icon = '🦯' }
    }
}
