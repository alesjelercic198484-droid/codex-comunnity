--[[
    codex_cryptomining - configuration
    ---------------------------------------------------------------
    Every gameplay value of the resource lives here. The script never
    trusts the client, so changing a value here changes it everywhere.

    Coordinates marked with "-- EDIT" are the ones you will most likely
    want to move to fit your own map / MLO setup.
]]

Config = {}

-- Prints extra information in the server & client console.
Config.Debug = false

-- Default locale, must match a file inside locales/ (en, fr).
Config.Locale = 'en'

Config.ESX = {
    UseExport = true,
    ExportName = 'es_extended',
    SharedObjectEvent = 'esx:getSharedObject'
}

Config.Database = {
    -- auto = oxmysql, then mysql-async, then ghmattimysql.
    Driver = 'auto',
    AutoCreate = true,
    -- How often (seconds) dirty rows are written back to MySQL.
    SaveInterval = 60
}

Config.Money = {
    -- Account used when the player buys something.
    BuyAccount = 'bank',
    -- Account credited when the player sells crypto / GPUs.
    SellAccount = 'bank',
    -- Account used by the black market.
    DirtyAccount = 'black_money',
    Symbol = '$'
}

Config.Inventory = {
    -- auto = ox_inventory when started, otherwise the ESX inventory.
    Type = 'auto',
    Items = {
        gpu = 'gpu',
        cpu = 'crypto_cpu',
        cooler = 'crypto_cooler',
        repairkit = 'crypto_repairkit',
        lockpick = 'lockpick',
        usb = 'hacking_usb',
        laptop = 'hacking_laptop'
    }
}

Config.Notifications = {
    -- The resource ships its OWN notification UI (html/), so it needs NO
    -- external dependency. Options:
    --   'builtin' = the integrated toast UI (default, zero dependency)
    --   'ox_lib'  = ox_lib lib.notify (only if you already run ox_lib)
    --   'esx'     = ESX ShowNotification
    --   'auto'    = builtin (kept for backwards compatibility)
    Type = 'builtin',
    Duration = 5000,
    Position = 'top-right'
}

Config.Target = {
    -- auto = ox_target, then qb-target, then the built in text UI.
    -- ox_target is the recommended (and only external) targeting dependency.
    Type = 'auto',
    Distance = 2.0
}

Config.Progress = {
    -- The resource ships its OWN progress bar UI (html/), no dependency needed.
    --   'builtin' = the integrated progress bar (default, zero dependency)
    --   'ox_lib'  = ox_lib lib.progressBar (only if you already run ox_lib)
    --   'esx'     = ESX Progressbar
    --   'auto'    = builtin
    Type = 'builtin'
}

Config.Dispatch = {
    Enabled = true,
    -- none | cd_dispatch | qs-dispatch | ps-dispatch | core_dispatch | rcore_dispatch | custom
    Type = 'none',
    Jobs = { 'police', 'sheriff', 'bcso' },
    Code = '10-31',
    Title = 'Crypto warehouse burglary',
    Message = 'Silent alarm triggered inside a crypto mining warehouse.',
    -- Fired when Type = 'custom'. Payload: { coords, title, message, code, jobs }
    CustomEvent = 'codex_cryptomining:dispatch'
}

Config.Webhooks = {
    Enabled = false,
    Name = 'CodeX CryptoMining',
    Avatar = '',
    Color = 3066993,
    -- Leave an URL empty to disable that specific log.
    Links = {
        warehouse = '',
        market = '',
        shop = '',
        robbery = '',
        admin = ''
    }
}

Config.Routing = {
    -- Every warehouse gets its own routing bucket so several players can use
    -- the same shared interior without seeing each other's rigs.
    Enabled = true,
    BaseBucket = 4100,
    -- 0 = strict (no world entities), 1 = relaxed. 1 is required for vehicles.
    LockdownMode = 1
}

-- ---------------------------------------------------------------------------
-- MINING ECONOMY
-- ---------------------------------------------------------------------------
Config.Mining = {
    -- Server tick used for production, electricity and wear (seconds).
    TickSeconds = 60,
    -- Maximum number of GPUs that can be installed in one rig.
    MaxGpusPerRig = 8,
    -- Price of an empty rig chassis bought from the warehouse panel.
    RigPrice = 9000,
    -- Ratio refunded when a rig is dismantled.
    RigSellRatio = 0.4,
    -- Raw hashrate (MH/s) produced by one GPU.
    HashPerGpu = 25.0,
    -- BTC generated per MH/s during one full hour.
    BtcPerHashHour = 0.0000045,
    -- Rigs keep mining while the owner is offline.
    OfflineMining = true,
    -- Multiplier applied to production when nobody of the crew is connected.
    OfflineMultiplier = 0.5,
    -- Maximum BTC a warehouse can hold before mining stops (0 = unlimited).
    StorageLimit = 25.0,
    Cpu = {
        MaxLevel = 3,
        -- Hashrate multiplier is 1 + (level * Bonus).
        Bonus = 0.15,
        Price = 4500
    },
    Cooler = {
        MaxLevel = 3,
        -- Each level removes this share of the disaster chance and of the wear.
        Bonus = 0.25,
        Price = 3800
    },
    Durability = {
        -- Durability lost per tick for a rig running at full load.
        LossPerTick = 0.35,
        -- Under this value the rig mines slower and breaks more often.
        WarningAt = 35.0,
        -- Production factor when durability is 0 (rig still spins, badly).
        MinFactor = 0.45,
        -- Durability restored by one repair kit.
        RepairAmount = 50.0,
        RepairDuration = 8000
    },
    Disaster = {
        Enabled = true,
        -- Base chance per rig and per tick (0.004 = 0.4%).
        Chance = 0.004,
        -- Extra chance applied linearly as durability drops to 0.
        WornMultiplier = 2.0,
        -- Chance to physically destroy one GPU when a disaster happens.
        GpuLossChance = 0.35
    }
}

Config.Electricity = {
    Enabled = true,
    -- kW used by the warehouse itself, even with no rig running.
    BaseLoad = 1.2,
    -- kW used by one rig chassis.
    RigLoad = 0.2,
    -- kW used by one GPU.
    GpuLoad = 0.35,
    -- Price of one kWh.
    PricePerKwh = 0.85,
    -- The power is cut when the unpaid bill goes over this amount.
    MaxDebt = 6000,
    -- Bill can be paid from this account.
    Account = 'bank'
}

Config.Market = {
    -- Starting price used the very first time the resource runs.
    StartPrice = 42000,
    MinPrice = 18000,
    MaxPrice = 92000,
    -- Seconds between two price updates.
    UpdateInterval = 300,
    -- Maximum move per update, in percent of the current price.
    Volatility = 0.045,
    -- Pull applied toward the middle of the range, keeps the market sane.
    MeanReversion = 0.08,
    -- Number of points kept for the chart / trend.
    HistorySize = 48,
    -- Fee taken by the exchange when a player sells BTC (0.02 = 2%).
    SellFee = 0.02
}

-- ---------------------------------------------------------------------------
-- INTERIORS
-- ---------------------------------------------------------------------------
-- Rig slots are generated as GPU banks split by a walkable central aisle, so
-- you do not have to write dozens of vectors by hand and the player can walk
-- up to every rig monitor. `gapCols` is how many column spacings are left
-- empty in the middle of each row (the aisle). Override `slots` with your own
-- list if you use a custom MLO.
local function GridSlots(origin, rows, cols, stepRight, stepForward, heading, gapCols)
    local slots = {}
    local rad = math.rad(heading or 0.0)
    local rightX, rightY = math.cos(rad), math.sin(rad)
    local fwdX, fwdY = -math.sin(rad), math.cos(rad)
    local halfBank = math.ceil(cols / 2)
    local gridHalf = ((cols + (gapCols or 0)) * 0.5) - 0.5

    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            -- Columns in the right half of the row are pushed across the aisle.
            local column = col
            if column >= halfBank then
                column = column + (gapCols or 0)
            end

            local right = (column - gridHalf) * stepRight
            local forward = row * stepForward

            slots[#slots + 1] = {
                x = origin.x + rightX * right + fwdX * forward,
                y = origin.y + rightY * right + fwdY * forward,
                z = origin.z,
                w = (heading or 0.0) % 360.0
            }
        end
    end

    return slots
end

-- Anchor of the base game Import / Export vehicle warehouse (Finance & Felony).
-- This interior ALWAYS exists on a vanilla server, it only needs its IPL to be
-- requested. Every coordinate below is built around this single verified point
-- so nothing spawns outside the room.
--   IPL   : imp_impexp_interior_placement_interior_1_impexp_intwaremed_milo_
--   Anchor: 994.5925, -3002.594, -39.64699   (upper level / vehicle floor)
local IMPEXP_IPL = 'imp_impexp_interior_placement_interior_1_impexp_intwaremed_milo_'
local IMPEXP_FLOOR = -39.64699
-- Grid origin sits ~4 m south of the entrance so the doorway and the storage
-- crate stay clear of the first rig row.
local IMPEXP_GRID = vector3(994.5925, -3006.50, IMPEXP_FLOOR)

Config.Interiors = {
    -- Both facility sizes reuse the SAME base game Import / Export vehicle
    -- warehouse (994.5925, -3002.594, -39.64699). Routing buckets keep every
    -- owner in their own private copy, so they never see each other's rigs even
    -- though the physical interior is shared. Only the rig capacity / layout
    -- changes between the two sizes.
    small = {
        label = 'Vehicle Warehouse (compact)',
        maxRigs = 12,
        -- IPL requested on the client. Leave empty when you stream your own MLO.
        ipls = { IMPEXP_IPL },
        -- Set to true when the interior comes from a streamed MLO: no IPL is
        -- requested and only the coordinates below are used.
        mlo = false,
        -- Where the player is teleported inside (the verified anchor point,
        -- facing the rig floor to the south).
        enter = vector4(994.5925, -3002.594, IMPEXP_FLOOR, 180.0), -- EDIT
        -- Where the player is teleported when leaving.
        exitOffset = vector4(0.0, 0.0, 0.0, 0.0),
        -- Management terminal (laptop prop + interaction), west of the entrance.
        terminal = vector4(990.00, -3002.60, IMPEXP_FLOOR, 90.0), -- EDIT
        -- Electricity panel (bill + power switch), east of the entrance.
        power = vector4(999.20, -3002.60, IMPEXP_FLOOR, 270.0), -- EDIT
        -- Storage crate used to drop / pick up GPUs, north of the entrance.
        storage = vector4(994.60, -3000.40, IMPEXP_FLOOR, 0.0), -- EDIT
        -- 6 columns x 2 rows = 12 slots in two banks, split by a ~4.8 m wide
        -- central aisle so the player can reach every rig monitor.
        slots = GridSlots(IMPEXP_GRID, 2, 6, 1.60, 1.70, 180.0, 2)
    },
    large = {
        label = 'Vehicle Warehouse (expanded)',
        maxRigs = 24,
        ipls = { IMPEXP_IPL },
        mlo = false,
        enter = vector4(994.5925, -3002.594, IMPEXP_FLOOR, 180.0), -- EDIT
        exitOffset = vector4(0.0, 0.0, 0.0, 0.0),
        terminal = vector4(990.00, -3002.60, IMPEXP_FLOOR, 90.0), -- EDIT
        power = vector4(999.20, -3002.60, IMPEXP_FLOOR, 270.0), -- EDIT
        storage = vector4(994.60, -3000.40, IMPEXP_FLOOR, 0.0), -- EDIT
        -- 8 columns x 3 rows = 24 slots in two banks, split by a ~4.8 m wide
        -- central aisle so the player can reach every rig monitor.
        slots = GridSlots(IMPEXP_GRID, 3, 8, 1.60, 1.70, 180.0, 2)
    }
}

-- Props spawned inside an interior. Models are validated at runtime and the
-- fallback is used when a model is missing from the player's game build.
-- IMPORTANT: every model below is a BASE GAME prop (no streamed files, no MLO
-- purchase required). Model names were verified against the GTA V object list.
-- If you replace one with an add-on prop, stream it yourself and make sure the
-- name is correct: an invalid model falls back to Config.Props.Fallback.
Config.Props = {
    Fallback = 'hei_prop_mini_sever_01',
    Rig = {
        -- Chassis, always spawned for an installed rig.
        -- hei_prop_mini_sever_01 is the small server rack from the Humane Labs
        -- heist: it looks exactly like a mining rig chassis.
        model = 'hei_prop_mini_sever_01',
        zOffset = 0.0,
        -- Small desk under the rig, set to false to disable.
        base = { model = 'prop_table_03', zOffset = -0.02, enabled = false }
    },
    -- One GPU prop is spawned per installed GPU, stacked on the rig.
    Gpu = {
        model = 'ex_office_swag_electronic',
        enabled = true,
        startOffset = vector3(0.0, 0.0, 0.62),
        perGpuOffset = vector3(0.0, 0.0, 0.11),
        maxVisual = 8
    },
    Cooler = {
        -- Desk fan from the Gunrunning bunker.
        model = 'gr_prop_bunker_deskfan_01a',
        enabled = true,
        offset = vector3(0.0, -0.45, 0.0)
    },
    -- Desktop monitor facing the aisle: this is the in-world computer the
    -- player walks up to in order to read the rig / wallet status. Set
    -- enabled = false to disable it (interactions still work without it).
    Monitor = {
        model = 'prop_monitor_03b',
        enabled = true,
        -- Offset from the rig chassis (local x, y, z): behind and above it.
        offset = vector3(0.0, -0.62, 0.98),
        -- Rotated 180° relative to the rig so the screen faces the aisle.
        heading = 180.0
    },
    Terminal = { model = 'prop_laptop_01a', zOffset = 0.92, enabled = true },
    PowerBox = { model = 'prop_elecbox_16', zOffset = 0.0, enabled = true },
    Storage = { model = 'prop_box_wood04a', zOffset = 0.0, enabled = true },
    -- Broken rigs get smoke + sparks.
    BrokenEffect = true,
    -- A rig that is broken can swap to a damaged looking model.
    BrokenModel = 'hei_prop_mini_sever_broken'
}

-- ---------------------------------------------------------------------------
-- WAREHOUSES
-- ---------------------------------------------------------------------------
-- `id` must stay unique and must not change once players own the warehouse.
Config.Warehouses = {
    {
        id = 'elysian',
        label = 'Elysian Island Depot',
        type = 'small',
        price = 185000,
        sellRatio = 0.55,
        entrance = vector4(-41.95, -2530.30, 6.01, 326.0), -- EDIT
        blip = { sprite = 492, color = 5, scale = 0.8 },
        electricity = 1.0
    },
    {
        id = 'lamesa',
        label = 'La Mesa Storage Unit',
        type = 'small',
        price = 210000,
        sellRatio = 0.55,
        entrance = vector4(826.42, -2145.90, 29.62, 268.0), -- EDIT
        blip = { sprite = 492, color = 5, scale = 0.8 },
        electricity = 1.15
    },
    {
        id = 'paleto',
        label = 'Paleto Bay Cold Store',
        type = 'small',
        price = 160000,
        sellRatio = 0.55,
        entrance = vector4(-279.02, 6226.55, 31.49, 45.0), -- EDIT
        blip = { sprite = 492, color = 5, scale = 0.8 },
        electricity = 0.85
    },
    {
        id = 'grandsenora',
        label = 'Grand Senora Bunker',
        type = 'large',
        price = 950000,
        sellRatio = 0.6,
        entrance = vector4(848.61, 2996.56, 45.81, 87.0), -- EDIT
        blip = { sprite = 557, color = 1, scale = 0.9 },
        electricity = 1.25
    },
    {
        id = 'ratoncanyon',
        label = 'Raton Canyon Bunker',
        type = 'large',
        price = 1150000,
        sellRatio = 0.6,
        entrance = vector4(-391.32, 4363.72, 58.65, 315.0), -- EDIT
        blip = { sprite = 557, color = 1, scale = 0.9 },
        electricity = 1.1
    }
}

Config.Blips = {
    Warehouse = { enabled = true, name = 'Crypto Warehouse', display = 4, shortRange = true },
    OwnedOnly = false,
    TechShop = { enabled = true, sprite = 606, color = 2, scale = 0.75, name = 'TechShop' },
    Broker = { enabled = true, sprite = 375, color = 46, scale = 0.75, name = 'Crypto Real Estate' },
    BlackMarket = { enabled = false, sprite = 133, color = 1, scale = 0.7, name = 'Black Market' },
    Informant = { enabled = false, sprite = 280, color = 5, scale = 0.7, name = 'Informant' }
}

-- ---------------------------------------------------------------------------
-- NPCs & SHOPS
-- ---------------------------------------------------------------------------
Config.Peds = {
    Freeze = true,
    Invincible = true,
    BlockEvents = true,
    -- Peds are only created within this distance (meters).
    SpawnDistance = 60.0
}

Config.TechShop = {
    Enabled = true,
    Model = 's_m_y_dealer_01',
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    Locations = {
        vector4(-660.05, -854.30, 24.49, 180.0), -- EDIT
        vector4(1137.60, -468.98, 66.73, 76.0)   -- EDIT
    },
    -- Items on sale. `item` is resolved through Config.Inventory.Items.
    Buy = {
        { item = 'gpu', label = 'Mining GPU', price = 6500 },
        { item = 'cpu', label = 'CPU upgrade kit', price = 4500 },
        { item = 'cooler', label = 'Cooling unit', price = 3800 },
        { item = 'repairkit', label = 'Repair kit', price = 1200 }
    },
    -- Ratio applied to the buy price when the player sells back.
    SellRatio = 0.45,
    MaxQuantity = 25
}

Config.BlackMarket = {
    Enabled = true,
    Model = 'g_m_m_armboss_01',
    Scenario = 'WORLD_HUMAN_SMOKING',
    Locations = {
        vector4(709.85, -963.55, 30.40, 89.0) -- EDIT
    },
    Account = 'black_money',
    Buy = {
        { item = 'lockpick', label = 'Reinforced lockpick', price = 2500 },
        { item = 'usb', label = 'Hacking USB drive', price = 4000 },
        { item = 'laptop', label = 'Hacking laptop', price = 12000 }
    },
    MaxQuantity = 10
}

Config.Informant = {
    Enabled = true,
    Model = 'a_m_y_business_02',
    Scenario = 'WORLD_HUMAN_STAND_MOBILE',
    Locations = {
        vector4(-1173.10, -1571.90, 4.66, 122.0) -- EDIT
    },
    Price = 15000,
    Account = 'black_money',
    -- How long the sold location stays marked (seconds).
    Duration = 900,
    -- Cooldown between two purchases for the same player (seconds).
    Cooldown = 600,
    -- Only sell warehouses that actually contain GPUs.
    OnlyLoaded = true
}

Config.Broker = {
    Enabled = true,
    Model = 'a_m_y_business_01',
    Scenario = 'WORLD_HUMAN_CLIPBOARD',
    Locations = {
        vector4(-716.30, 261.55, 84.14, 115.0) -- EDIT
    },
    -- Maximum number of warehouses a single player can own.
    MaxPerPlayer = 2
}

-- ---------------------------------------------------------------------------
-- ROBBERY
-- ---------------------------------------------------------------------------
Config.Robbery = {
    Enabled = true,
    MinPolice = 2,
    PoliceJobs = { 'police', 'sheriff', 'bcso' },
    -- Max robberies running at the same time on the whole server.
    MaxSimultaneous = 2,
    -- Cooldown for the thief (seconds).
    PlayerCooldown = 1800,
    -- Cooldown for the warehouse (seconds).
    WarehouseCooldown = 3600,
    -- The warehouse must contain at least this many GPUs to be robbable.
    MinGpus = 4,
    -- A robbery expires automatically after this delay (seconds).
    Timeout = 900,
    -- Tools consumed / required.
    RequireLockpick = true,
    ConsumeLockpick = true,
    LockpickBreakChance = 0.25,
    RequireUsb = true,
    ConsumeUsb = true,
    -- Time to loot a single rig (ms).
    LootDuration = 6000,
    -- Share of the GPUs actually recovered from a looted rig.
    LootRatio = 1.0,
    -- Notify the owner when his warehouse is attacked.
    NotifyOwner = true,
    -- Alarm & dispatch.
    Dispatch = true,
    Minigames = {
        -- The resource ships its OWN skillcheck minigame (html/), so no
        -- dependency is required.
        --   Door: 'builtin' | 'lockpick' | 'ox_skillcheck' | 'none'
        Door = 'builtin',
        --   Rig:  'builtin' | 'hack' | 'ox_skillcheck' | 'none'
        Rig = 'builtin',
        -- Difficulty list: one entry = one round the player must clear.
        -- 'easy' | 'medium' | 'hard' control the ring speed / hit window.
        Difficulty = { 'easy', 'easy', 'medium' }
    }
}

Config.Commands = {
    -- Opens the warehouse panel when the player stands inside one of his
    -- warehouses. Set to false to disable.
    Panel = 'cryptopanel',
    -- Admin command, needs the ace permission below.
    Admin = 'crypto',
    AcePermission = 'codex_cryptomining.admin'
}

Config.KeyBinding = {
    -- No key is registered by default.
    Enabled = false,
    Key = 'F7'
}
