--[[
    codex_policecreator - configuration

    Everything a server owner can change lives here. Nothing in this resource
    requires you to touch qb-core/shared/jobs.lua: departments are stored in
    their own tables and members are linked by citizenid.
]]

Config = {}

Config.Debug = false

-- 'auto' picks QBCore when it is running, otherwise ESX.
-- Set it explicitly to 'qbcore' or 'esx' to skip detection.
Config.Framework = 'auto'

-- Money account used for cash payouts / charges (QBCore: 'cash'|'bank', ESX: 'money'|'bank').
Config.MoneyAccount = 'bank'

-- ---------------------------------------------------------------------------
-- KEYS / CONTROLS
-- ---------------------------------------------------------------------------
Config.Keys = {
    Interact = 38,   -- E  -> use the node you are standing on
    BossMenu = 0,    -- 0 disables the hotkey (use the boss menu node instead)
    Siren = 85,      -- Z  -> unmarked siren / light pattern menu
    Handcuff = 0,    -- 0 disables
    Animations = 0   -- 0 disables (command /anims always works)
}

Config.Commands = {
    Creator = 'deptcreator', -- create departments & place nodes
    Menu = 'dept',           -- open the boss menu for your department
    Duty = 'duty',           -- toggle on/off duty
    Anims = 'anims',         -- animation list
    Call = '911',            -- civilian emergency call
    CallMedic = '912',       -- civilian EMS call
    K9 = 'k9'                -- K9 interaction menu
}

-- Ace permissions. Set to false to allow everybody (or restrict via Config.Creator.Jobs).
Config.Ace = {
    Creator = 'codex_policecreator.creator',
    Admin = 'codex_policecreator.admin'
}

-- Fallback when you do not use ACE: these QBCore/ESX jobs may always use the creator.
Config.CreatorJobs = { 'admin', 'god', 'superadmin' }

-- ---------------------------------------------------------------------------
-- TARGET (optional). Leave Enabled = false to use the built-in E prompt.
-- ---------------------------------------------------------------------------
Config.Target = {
    Enabled = false,
    Resource = 'ox_target', -- 'ox_target' or 'qb-target'
    Distance = 2.2,
    Icon = 'fa-solid fa-building-shield'
}

-- ---------------------------------------------------------------------------
-- DEPARTMENT TEMPLATES
-- Used by the in-game creator. Every template can be edited / duplicated in
-- the NUI creator, these are just the starting presets.
-- ---------------------------------------------------------------------------
Config.DepartmentTemplates = {
    police = {
        Label = 'Police Department',
        Type = 'police',
        Color = '#2f6df6',
        BlipSprite = 60,
        BlipColor = 29,
        BlipScale = 0.9,
        DefaultSalary = 250,
        StartingFunds = 25000,
        Ranks = {
            { label = 'Cadet',        salary = 150, perms = { 'dispatch', 'evidence' } },
            { label = 'Officer',      salary = 200, perms = { 'dispatch', 'evidence', 'garage', 'armory' } },
            { label = 'Corporal',     salary = 260, perms = { 'dispatch', 'evidence', 'garage', 'armory', 'bolo' } },
            { label = 'Sergeant',     salary = 320, perms = { 'dispatch', 'evidence', 'garage', 'armory', 'bolo', 'manage', 'applications', 'cameras' } },
            { label = 'Lieutenant',   salary = 400, perms = { 'dispatch', 'evidence', 'garage', 'armory', 'bolo', 'manage', 'applications', 'cameras', 'finance', 'trackers' } },
            { label = 'Chief',        salary = 500, boss = true, perms = { 'all' } }
        }
    },

    sheriff = {
        Label = 'Sheriff Office',
        Type = 'police',
        Color = '#c8a24a',
        BlipSprite = 60,
        BlipColor = 5,
        BlipScale = 0.9,
        DefaultSalary = 250,
        StartingFunds = 20000,
        Ranks = {
            { label = 'Deputy',       salary = 180, perms = { 'dispatch', 'evidence' } },
            { label = 'Corporal',     salary = 240, perms = { 'dispatch', 'evidence', 'garage', 'armory' } },
            { label = 'Sergeant',     salary = 310, perms = { 'dispatch', 'evidence', 'garage', 'armory', 'bolo', 'manage' } },
            { label = 'Sheriff',      salary = 460, boss = true, perms = { 'all' } }
        }
    },

    fib = {
        Label = 'Federal Investigation Bureau',
        Type = 'police',
        Color = '#1d2733',
        BlipSprite = 60,
        BlipColor = 1,
        BlipScale = 0.9,
        DefaultSalary = 400,
        StartingFunds = 60000,
        Ranks = {
            { label = 'Agent',            salary = 350, perms = { 'dispatch', 'evidence', 'garage', 'armory' } },
            { label = 'Special Agent',    salary = 450, perms = { 'dispatch', 'evidence', 'garage', 'armory', 'bolo', 'cameras', 'trackers' } },
            { label = 'Supervisory Agent', salary = 550, perms = { 'dispatch', 'evidence', 'garage', 'armory', 'bolo', 'cameras', 'trackers', 'manage', 'finance' } },
            { label = 'Director',         salary = 700, boss = true, perms = { 'all' } }
        }
    },

    highway = {
        Label = 'Highway Patrol',
        Type = 'police',
        Color = '#2f8f5b',
        BlipSprite = 60,
        BlipColor = 25,
        BlipScale = 0.9,
        DefaultSalary = 260,
        StartingFunds = 18000,
        Ranks = {
            { label = 'Trooper',          salary = 200, perms = { 'dispatch', 'evidence', 'garage', 'armory' } },
            { label = 'Senior Trooper',   salary = 270, perms = { 'dispatch', 'evidence', 'garage', 'armory', 'bolo' } },
            { label = 'Commander',        salary = 400, boss = true, perms = { 'all' } }
        }
    },

    ems = {
        Label = 'Emergency Medical Services',
        Type = 'ems',
        Color = '#e0483f',
        BlipSprite = 61,
        BlipColor = 1,
        BlipScale = 0.9,
        DefaultSalary = 220,
        StartingFunds = 20000,
        Ranks = {
            { label = 'EMT',         salary = 160, perms = { 'dispatch', 'garage' } },
            { label = 'Paramedic',   salary = 220, perms = { 'dispatch', 'garage', 'armory' } },
            { label = 'Doctor',      salary = 320, perms = { 'dispatch', 'garage', 'armory', 'manage', 'applications' } },
            { label = 'Chief Doctor', salary = 450, boss = true, perms = { 'all' } }
        }
    },

    custom = {
        Label = 'New Department',
        Type = 'custom',
        Color = '#8b5cf6',
        BlipSprite = 1,
        BlipColor = 4,
        BlipScale = 0.85,
        DefaultSalary = 200,
        StartingFunds = 10000,
        Ranks = {
            { label = 'Recruit',  salary = 150, perms = { 'dispatch' } },
            { label = 'Officer',  salary = 220, perms = { 'dispatch', 'evidence', 'garage', 'armory' } },
            { label = 'Chief',    salary = 350, boss = true, perms = { 'all' } }
        }
    }
}

-- Node types the creator can place. `unique` = only one per department.
Config.NodeTypes = {
    boss = { label = 'Boss menu / office PC', unique = true,  marker = { type = 1, color = { 47, 109, 246 } }, ped = { model = 's_m_y_cop_01', scenario = 'WORLD_HUMAN_CLIPBOARD' } },
    armory = { label = 'Armory',              unique = false, marker = { type = 1, color = { 240, 130, 40 } },  ped = nil },
    garage = { label = 'Vehicle garage',      unique = false, marker = { type = 1, color = { 60, 190, 120 } },  ped = nil },
    impound = { label = 'Impound lot',        unique = false, marker = { type = 1, color = { 200, 60, 60 } },   ped = nil },
    evidence = { label = 'Evidence board',    unique = false, marker = { type = 1, color = { 220, 200, 60 } },  ped = nil },
    computer = { label = 'Dispatch computer', unique = false, marker = { type = 1, color = { 120, 90, 220 } },  ped = nil },
    locker = { label = 'Locker room',         unique = false, marker = { type = 1, color = { 90, 160, 220 } },  ped = nil }
}

-- Interact distance for a node prompt, and the blip shown on the map.
Config.NodeRange = 2.0
Config.NodeBlips = {
    boss = { sprite = 351, color = 29, scale = 0.8 },
    armory = { sprite = 108, color = 40, scale = 0.8 },
    garage = { sprite = 357, color = 25, scale = 0.8 },
    impound = { sprite = 357, color = 1, scale = 0.8 },
    evidence = { sprite = 303, color = 5, scale = 0.8 },
    computer = { sprite = 521, color = 26, scale = 0.8 },
    locker = { sprite = 272, color = 3, scale = 0.8 }
}
Config.ShowNodeBlipsToMembersOnly = true

-- ---------------------------------------------------------------------------
-- ARMORY (3D rack view is client side, this is the data)
-- ---------------------------------------------------------------------------
Config.Armory = {
    -- 3D presentation of the issued loadout on a rack near the armory node.
    Display3D = true,
    DisplayModel = 'prop_gun_case_01',
    DisplayOffset = vector3(0.0, 0.9, 0.0),

    -- rank = minimum department grade that may take the item.
    Items = {
        { item = 'WEAPON_FLASHLIGHT',       label = 'Flashlight',      rank = 0, ammo = 0 },
        { item = 'WEAPON_NIGHTSTICK',       label = 'Nightstick',      rank = 0, ammo = 0 },
        { item = 'WEAPON_STUNGUN',          label = 'Taser',           rank = 1, ammo = 0 },
        { item = 'WEAPON_COMBATPISTOL',     label = 'Combat pistol',   rank = 1, ammo = 60 },
        { item = 'WEAPON_CARBINERIFLE',     label = 'Carbine rifle',   rank = 3, ammo = 180 },
        { item = 'WEAPON_PUMPSHOTGUN',      label = 'Pump shotgun',    rank = 2, ammo = 60 },
        { item = 'WEAPON_SMG',              label = 'SMG',             rank = 4, ammo = 150 },
        { item = 'handcuffs',               label = 'Handcuffs',       rank = 0, ammo = 0 },
        { item = 'radio',                   label = 'Radio',           rank = 0, ammo = 0 },
        { item = 'codex_evidence_bag',      label = 'Evidence bags',   rank = 0, ammo = 0, amount = 10 },
        { item = 'codex_tracker',           label = 'GPS tracker',     rank = 3, ammo = 0, amount = 2 },
        { item = 'armor',                   label = 'Body armor',      rank = 1, ammo = 0 },
        { item = 'firstaid',                label = 'First aid',       rank = 0, ammo = 0, amount = 5 }
    },

    -- Weapons get a serial number stored in the item metadata (ox_inventory / qb-weapons).
    Serials = {
        Enabled = true,
        Prefix = 'PC',
        MetadataKey = 'serial'
    },

    -- true: taking an item removes it from the armory (nothing to buy back).
    -- false: items are simply given (infinite armory).
    LimitedStock = false,
    Stock = {} -- filled at runtime when LimitedStock = true
}

-- ---------------------------------------------------------------------------
-- EVIDENCE
-- ---------------------------------------------------------------------------
Config.Evidence = {
    BagItem = 'codex_evidence_bag',
    RequireBag = true,
    MaxRange = 3.0,        -- how far from the node you may still submit evidence
    CollectDistance = 2.5, -- how close to a crime scene marker you must be
    Grades = {
        { level = 1, label = 'Low',      color = '#8ab4f8' },
        { level = 2, label = 'Medium',   color = '#f7c948' },
        { level = 3, label = 'High',     color = '#f2803c' },
        { level = 4, label = 'Critical', color = '#e0483f' }
    },
    -- Evidence auto-expires (hours). 0 = keep forever.
    ExpireHours = 0,
    FlashlightModel = 'prop_cs_torch_01'
}

-- ---------------------------------------------------------------------------
-- DISPATCH
-- ---------------------------------------------------------------------------
Config.Dispatch = {
    BlipSprite = 304,
    BlipColor = 1,
    BlipScale = 1.2,
    BlipAlpha = 180,
    Radius = 25.0,
    KeepLogsDays = 30,
    MaxOpenCalls = 40,

    Codes = {
        { code = '10-31', label = 'Crime in progress',  type = 'police', priority = 3 },
        { code = '10-50', label = 'Traffic accident',   type = 'police', priority = 2 },
        { code = '10-70', label = 'Fire',               type = 'ems',    priority = 3 },
        { code = '10-54', label = 'Medical emergency',  type = 'ems',    priority = 3 },
        { code = '10-90', label = 'Bank alarm',         type = 'police', priority = 4 },
        { code = '10-99', label = 'Officer needs help', type = 'police', priority = 4 },
        { code = '10-16', label = 'Domestic dispute',   type = 'police', priority = 2 },
        { code = '10-66', label = 'Suspicious person',  type = 'police', priority = 1 }
    },

    -- Civilians can call with /911 (or a phone integration calling the export).
    CivilianCall = true,
    CallCooldown = 60, -- seconds between two calls from the same player

    Sound = {
        Enabled = true,
        Name = 'Event_Start_Text',
        Set = 'GTAO_FM_Events_Soundset'
    }
}

-- ---------------------------------------------------------------------------
-- ALPR + BOLO
-- ---------------------------------------------------------------------------
Config.ALPR = {
    Enabled = true,
    Interval = 2500,   -- ms between plate scans
    Range = 22.0,      -- metres in front of the vehicle
    ConeAngle = 60,    -- degrees
    RequireDuty = true,
    NotifyCooldown = 30 -- seconds before the same plate alerts again
}

Config.Bolo = {
    MaxActive = 50,
    Types = {
        { type = 'plate',  label = 'Vehicle plate' },
        { type = 'person', label = 'Person' },
        { type = 'vehicle', label = 'Vehicle model' }
    }
}

-- ---------------------------------------------------------------------------
-- GARAGE
-- ---------------------------------------------------------------------------
Config.Garage = {
    -- Fallback vehicles for a department that has none in the database yet.
    Defaults = {
        { model = 'police',  label = 'Police Cruiser',  rank = 0, livery = -1 },
        { model = 'police2', label = 'Police Cruiser 2', rank = 1, livery = -1 },
        { model = 'police3', label = 'Unmarked Cruiser', rank = 2, livery = -1 },
        { model = 'policeb', label = 'Police Bike',      rank = 2, livery = -1 },
        { model = 'policet', label = 'Police Transport', rank = 3, livery = -1 },
        { model = 'riot',    label = 'RIOT',             rank = 5, livery = -1 },
        { model = 'ambulance', label = 'Ambulance',      rank = 0, livery = -1, type = 'ems' }
    },

    SaveStateOnReturn = true, -- store fuel + body/engine health
    DeleteOnReturn = true,
    ReturnRange = 6.0,
    SpawnClearRange = 3.0, -- clear the spawn point of stray vehicles before spawning
    MaxOutPerPlayer = 1,   -- 0 = unlimited
    ImpoundFee = 500       -- paid from department funds when a boss un-impounds
}

-- ---------------------------------------------------------------------------
-- CAMERAS
-- ---------------------------------------------------------------------------
Config.Cameras = {
    Model = 'prop_cctv_cam_01a',
    Fov = 70.0,
    FreeLookSpeed = 3.0,
    MaxCams = 200,
    NightVision = true
}

-- ---------------------------------------------------------------------------
-- GPS TRACKERS
-- ---------------------------------------------------------------------------
Config.Trackers = {
    Item = 'codex_tracker',
    UpdateInterval = 4000, -- ms between position updates from the placing client
    PlaceTime = 6000,      -- ms of the attach animation
    MaxActivePerDept = 10,
    ExpireHours = 48,      -- 0 = never
    Anims = { dict = 'anim@amb@nightclub@lazlow@ig1_vip@', clip = 'clubvip_base_laz', flag = 49 }
}

-- ---------------------------------------------------------------------------
-- UNMARKED SIRENS
-- ---------------------------------------------------------------------------
Config.Sirens = {
    -- Any civilian vehicle can be turned into an unmarked unit.
    Enabled = true,
    RequireOnDuty = false,
    MenuKey = 85,
    Patterns = {
        { label = 'Stage 1 - lights only',     siren = false, muted = true,  extras = { [1] = true,  [2] = false, [3] = false, [4] = false } },
        { label = 'Stage 2 - lights + siren',  siren = true,  muted = false, extras = { [1] = true,  [2] = true,  [3] = false, [4] = false } },
        { label = 'Stage 3 - full emergency',  siren = true,  muted = false, extras = { [1] = true,  [2] = true,  [3] = true,  [4] = true } },
        { label = 'Off',                       siren = false, muted = true,  extras = { [1] = false, [2] = false, [3] = false, [4] = false } }
    },
    InteriorLight = true
}

-- ---------------------------------------------------------------------------
-- ANIMATIONS (30+)
-- ---------------------------------------------------------------------------
Config.Animations = {
    { category = 'Police', label = 'Traffic stop - halt',   dict = 'random@arrests',            clip = 'idle_2_hands_up',         duration = 4000 },
    { category = 'Police', label = 'Radio check',           dict = 'random@arrests',            clip = 'generic_radio_chatter', duration = 6000 },
    { category = 'Police', label = 'Take notes',            dict = 'amb@code_human_police@investigate@idle_a', clip = 'idle_a', duration = 8000 },
    { category = 'Police', label = 'Stand guard',           dict = 'amb@world_human_stand_guard@male@base', clip = 'base',        duration = 0, loop = true },
    { category = 'Police', label = 'Crouch cover',          dict = 'combat@gestures@duck@cover', clip = '0',                    duration = 0, loop = true },
    { category = 'Police', label = 'Search vehicle',        dict = 'mini@prostitutes@3lowsexfemale', clip = 'idle_a',         duration = 5000 },
    { category = 'Police', label = 'Point forward',         dict = 'anim@mp_point',             clip = '240_loop',                duration = 4000 },
    { category = 'Police', label = 'Kneel - inspect',       dict = 'amb@medic@kneel@base',      clip = 'base',                    duration = 0, loop = true },
    { category = 'Police', label = 'Wave traffic through',  dict = 'random@car_4',              clip = 'johnnyboyes_loop_a',      duration = 5000 },
    { category = 'Police', label = 'Hands on hips',         dict = 'amb@world_human_bum_bin@male@base', clip = 'base',        duration = 0, loop = true },
    { category = 'Police', label = 'Arrest - cuff front',   dict = 'mp_arresting',              clip = 'a_uncuff',                duration = 6000 },
    { category = 'Police', label = 'Arrest - idle cuffed',  dict = 'mp_arresting',              clip = 'idle',                    duration = 0, loop = true },
    { category = 'Police', label = 'Push suspect',          dict = 'mp_arresting',              clip = 'b_uncuff',                duration = 5000 },
    { category = 'Police', label = 'Salute',                dict = 'anim@mp_player_intsalute',  clip = 'idle_a',                  duration = 3500 },
    { category = 'Police', label = 'Lean on wall',          dict = 'amb@world_human_lean@male@wall@base', clip = 'base',      duration = 0, loop = true },
    { category = 'Police', label = 'Binoculars',            dict = 'amb@world_human_binoculars@male@base', clip = 'base',     duration = 0, loop = true },
    { category = 'Medical', label = 'CPR',                  dict = 'mini@cpr@char_a@cpr_str',   clip = 'cpr_pumpchest',           duration = 10000 },
    { category = 'Medical', label = 'Treat patient',        dict = 'amb@medic@standing@tend_to_patient@base', clip = 'base', duration = 0, loop = true },
    { category = 'Medical', label = 'Carry stretcher',      dict = 'anim@gang_transport_stretcher', clip = 'idle',            duration = 0, loop = true },
    { category = 'Medical', label = 'Kneel - check pulse',  dict = 'amb@medic@kneel@idle_a',    clip = 'idle_a',                  duration = 6000 },
    { category = 'Medical', label = 'Defibrillator',        dict = 'amb@medic@standing@defib@base', clip = 'base',             duration = 8000 },
    { category = 'Civilian', label = 'Surrender',           dict = 'random@arrests@busted',     clip = 'idle_c',                  duration = 0, loop = true },
    { category = 'Civilian', label = 'Hands up',            dict = 'random@arrests',            clip = 'kneeling_arrest_idle',    duration = 0, loop = true },
    { category = 'Civilian', label = 'Kneel down',          dict = 'random@arrests',            clip = 'idle_a',                  duration = 0, loop = true },
    { category = 'Civilian', label = 'Sit - injured',       dict = 'amb@world_human_bum_wash@male@low@base', clip = 'base',    duration = 0, loop = true },
    { category = 'Civilian', label = 'Panic',               dict = 'missfbi4',                  clip = 'guard_react_thrownpepperspray', duration = 6000 },
    { category = 'Civilian', label = 'Lean - smoking',      dict = 'amb@world_human_leaning@male@wall@base', clip = 'base',     duration = 0, loop = true },
    { category = 'Civilian', label = 'Lay down',            dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop', duration = 0, loop = true },
    { category = 'Civilian', label = 'Beg',                 dict = 'amb@world_human_bum_bin@male@idle_a', clip = 'idle_c',     duration = 5000 },
    { category = 'Civilian', label = 'Wave - friendly',     dict = 'anim@mp_player_intcelebrationpaired@f@wave', clip = 'wave', duration = 3000 },
    { category = 'Casual', label = 'Sit on ground',         dict = 'anim@heists@ornate_bank@hostages@hit', clip = 'hit_loop_ped_b', duration = 0, loop = true },
    { category = 'Casual', label = 'Cross arms',            dict = 'amb@world_human_hang_out_street@male_b@base', clip = 'base', duration = 0, loop = true },
    { category = 'Casual', label = 'Look around nervous',   dict = 'misscarsteal2leadin',       clip = 'idle_a_frustrated',         duration = 6000 },
    { category = 'Casual', label = 'Stretch',               dict = 'amb@world_human_jog_standing@male@idle_a', clip = 'idle_d',  duration = 6000 },
    { category = 'Casual', label = 'Think',                 dict = 'amb@world_human_stupor@male@base', clip = 'base',           duration = 0, loop = true }
}

-- ---------------------------------------------------------------------------
-- K9
-- ---------------------------------------------------------------------------
Config.K9 = {
    Enabled = true,
    MinRank = 2,
    Model = 'a_c_shepherd',
    FollowDistance = 3.0,
    Command = 'k9',
    -- Items a K9 can sniff out on a player.
    Contraband = { 'weed', 'cocaine', 'meth', 'heroin', 'oxy' },
    SniffRange = 4.0,
    VehicleSniffRange = 3.5,
    SpawnItem = 'k9_kennel' -- optional: require this item to deploy. '' = no item needed
}

-- ---------------------------------------------------------------------------
-- RADIO (optional pma-voice bridge)
-- ---------------------------------------------------------------------------
Config.Radio = {
    Enabled = false,
    Resource = 'pma-voice',
    -- Department radio channel number. Keep it above 999 so it never collides
    -- with normal player channels.
    ChannelOffset = 1000
}

-- ---------------------------------------------------------------------------
-- DUTY / SALARIES
-- ---------------------------------------------------------------------------
Config.Duty = {
    LogToDatabase = true,
    SalaryInterval = 600000, -- 10 minutes
    PayOnlyOnDuty = false,   -- true: only pay members that are on duty at payout time
    MaxDutyHoursPerDay = 0   -- 0 = no limit
}

-- ---------------------------------------------------------------------------
-- CREATOR LIMITS
-- ---------------------------------------------------------------------------
Config.Creator = {
    MaxDepartments = 50,
    MaxNodesPerDepartment = 40,
    MaxRanks = 20,
    MaxDivisions = 25,
    MinDistanceBetweenNodes = 3.0,
    SeedDefaults = true -- seed a default Police Department on first start
}

-- ---------------------------------------------------------------------------
-- DATABASE
-- ---------------------------------------------------------------------------
Config.DB = {
    AutoCreateTables = true,
    Prefix = 'codex_pc_'
}

Config.Version = '1.0.0'
