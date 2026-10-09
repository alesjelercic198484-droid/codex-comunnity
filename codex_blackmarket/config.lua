-- codex_blackmarket: QBCore black market, cargo runs and private storage.
-- Move all coordinates below to fit your server's map/MLOs.
Config = {}

Config.Debug = false
Config.ResourceLabel = 'Black Market'

-- OneSync is required for secure server-side distance checks.
Config.Security = {
    RequireOneSync = true,
    VendorDistance = 8.0,
    WarehouseDistance = 4.0,
    PickupDistance = 5.0,
    DropDistance = 8.0,
    MaxQuantityPerItem = 25,
    MaxCartLines = 10,
    MaxSellQuantity = 100,
    ActionCooldownMs = 900
}

-- Contact is available from 22:00 through 10:00 (GTA world time).
-- This schedule controls the client interaction/visibility; server-side
-- transactions are still protected by proximity, stock and item checks.
Config.MarketHours = {
    Enabled = true,
    Open = 22,
    Close = 10
}

Config.Dealer = {
    -- Default location: the Port of Los Santos. Edit for your map.
    Vendors = {
        {
            id = 'docks',
            label = 'Dockside Contact',
            coords = vector4(1205.53, -3114.98, 5.54, 91.0),
            ped = 'g_m_y_mexgoon_02',
            scenario = 'WORLD_HUMAN_LEANING',
            van = 'speedo',
            vanCoords = vector4(1211.5, -3114.4, 5.54, 90.0),
            targetDistance = 2.2
        }
    }
}

Config.Progression = {
    -- Index is access level, value is the XP needed to reach that level.
    LevelThresholds = { 0, 100, 250, 450, 700, 1000 },
    MaxRespect = 1000
}

Config.Categories = {
    { id = 'tools',    label = 'Tools',          icon = '⌁', minLevel = 1, description = 'Entry tools and hardware.' },
    { id = 'weapons',  label = 'Weapons',        icon = '✦', minLevel = 2, description = 'Unregistered hardware.' },
    { id = 'ammo',     label = 'Ammunition',     icon = '◉', minLevel = 2, description = 'Limited ammunition stock.' }
}

-- Items must exist in qb-core/shared/items.lua. Items missing from that shared
-- table are skipped safely and reported in the server console.
Config.MarketItems = {
    { item = 'lockpick',              category = 'tools',   label = 'Lockpick',             icon = '⌁', price = 450,   stock = 60, maxStock = 100, restock = 8,  level = 1, description = 'A basic pick for simple locks.' },
    { item = 'advancedlockpick',      category = 'tools',   label = 'Advanced Lockpick',    icon = '⌗', price = 4200,  stock = 28, maxStock = 45,  restock = 4,  level = 2, description = 'A tougher pick for reinforced locks.' },
    { item = 'electronickit',         category = 'tools',   label = 'Electronic Kit',       icon = '⌘', price = 6200,  stock = 22, maxStock = 36,  restock = 3,  level = 3, description = 'A compact kit for bypassing electronics.' },
    { item = 'trojan_usb',            category = 'tools',   label = 'Encrypted USB',        icon = '▣', price = 9500,  stock = 16, maxStock = 28,  restock = 2,  level = 4, description = 'A one-use key for high-security systems.' },
    { item = 'thermite',              category = 'tools',   label = 'Thermite Charge',      icon = '✧', price = 14000, stock = 12, maxStock = 20,  restock = 1,  level = 5, description = 'Handle with care. Serious jobs only.' },

    { item = 'weapon_pistol',         category = 'weapons', label = 'Compact Pistol',       icon = '⌖', price = 32000, stock = 12, maxStock = 20,  restock = 1,  level = 2, maxPurchase = 1, description = 'No paperwork. No questions.' },
    { item = 'weapon_microsmg',       category = 'weapons', label = 'Micro SMG',            icon = '⌖', price = 87000, stock = 7,  maxStock = 12,  restock = 1,  level = 4, maxPurchase = 1, description = 'A compact automatic weapon.' },
    { item = 'weapon_sawnoffshotgun', category = 'weapons', label = 'Sawed-off Shotgun',    icon = '⌖', price = 99000, stock = 5,  maxStock = 10,  restock = 1,  level = 5, maxPurchase = 1, description = 'Short range. Big consequences.' },

    { item = 'pistol_ammo',           category = 'ammo',    label = 'Pistol Ammunition',    icon = '◉', price = 900,   stock = 80, maxStock = 120, restock = 12, level = 2, description = 'Standard pistol rounds.' },
    { item = 'smg_ammo',              category = 'ammo',    label = 'SMG Ammunition',       icon = '◉', price = 1600,  stock = 45, maxStock = 80,  restock = 8,  level = 4, description = 'Ammunition for compact automatics.' },
    { item = 'shotgun_ammo',          category = 'ammo',    label = 'Shotgun Shells',       icon = '◉', price = 1900,  stock = 35, maxStock = 60,  restock = 6,  level = 5, description = 'A small box of 12-gauge shells.' }
}

Config.MarketPricing = {
    -- Low stock raises the price. Sell transactions can replenish stock only
    -- when a sell item also exists in the market catalog.
    ScarcityMarkup = 0.65,
    MinMultiplier = 0.75,
    MaxMultiplier = 1.80
}

Config.Payment = {
    AllowedAccounts = {
        cash = { label = 'Cash' },
        bank = { label = 'Bank' }
    },
    DefaultAccount = 'cash'
}

Config.SellOffers = {
    -- These offers are hidden unless the item is registered in QBCore.
    { item = 'cryptostick', label = 'Encrypted Data Stick', icon = '▣', price = 1250, description = 'Recovered data. The contact pays per stick.' },
    { item = 'weed_brick',  label = 'Compressed Package',   icon = '▰', price = 5500, description = 'Bulk contraband, sold discreetly.' },
    { item = 'cokebaggy',   label = 'Powder Packet',        icon = '◈', price = 950,  description = 'Small sealed packet.' },
    { item = 'meth',        label = 'Crystal Package',      icon = '◇', price = 1200, description = 'A small package for the buyer.' }
}

Config.Cargo = {
    Enabled = true,
    RequireDriver = true,
    Pickup = vector3(1203.2, -3112.2, 5.54),
    CrateModel = 'prop_box_wood02a',
    MissionLifetimeMinutes = 120,
    MinimumStopSeconds = 3,
    Tiers = {
        [1] = { label = 'Local Courier',  minLevel = 1, deposit = 0,     reward = 4500,  xp = 40,  respect = 5,  drops = 1, packages = 1, description = 'A short local handoff. Use your own road vehicle.' },
        [2] = { label = 'Regional Run',   minLevel = 2, deposit = 2500,  reward = 9500,  xp = 75,  respect = 10, drops = 2, packages = 2, description = 'Two stops with a larger package. Keep a low profile.' },
        [3] = { label = 'Priority Cargo', minLevel = 4, deposit = 8000,  reward = 19000, xp = 125, respect = 18, drops = 3, packages = 3, description = 'Three high-risk handoffs. Best payout and reputation.' }
    },
    Routes = {
        {
            id = 'city-east',
            label = 'East Los Santos',
            drops = {
                vector3(1194.4, -1265.8, 35.2),
                vector3(978.6, -1824.9, 31.2),
                vector3(730.4, -966.5, 24.1)
            }
        },
        {
            id = 'city-south',
            label = 'Southside Circuit',
            drops = {
                vector3(842.5, -2172.1, 29.6),
                vector3(413.2, -2067.9, 21.1),
                vector3(256.4, -1730.2, 29.7)
            }
        },
        {
            id = 'county',
            label = 'County Drop',
            drops = {
                vector3(1546.4, 6335.7, 24.1),
                vector3(1691.5, 4922.4, 42.1),
                vector3(1965.3, 4634.2, 40.5)
            }
        }
    }
}

-- Each player gets a private persistent qb-inventory stash and a six-digit
-- passcode for every warehouse they have unlocked.
Config.Warehouses = {
    { id = 'harbor', label = 'Harbor Storage',   coords = vector3(1009.2, -2512.0, 28.3), minLevel = 1, slots = 40, maxWeight = 250000 },
    { id = 'desert', label = 'Desert Depot',     coords = vector3(1392.6, 3605.4, 38.9),  minLevel = 3, slots = 50, maxWeight = 350000 },
    { id = 'industrial', label = 'Industrial Unit', coords = vector3(895.8, -2171.8, 32.3), minLevel = 5, slots = 60, maxWeight = 500000 }
}

Config.Database = {
    AutoCreate = true,
    RestockIntervalMinutes = 30
}

Config.Admin = {
    Command = 'bmadmin',
    AcePermission = 'codex_blackmarket.admin',
    MaxPrice = 1000000,
    MaxStock = 10000
}

Config.Notifications = {
    Title = 'Black Market',
    ContactClosed = 'The contact is not available right now. Check back between 22:00 and 10:00.',
    TooFar = 'Move closer to the contact or terminal.',
    NeedVehicle = 'You need to be in the driver seat of a vehicle.',
    MissionActive = 'You already have an active cargo run.',
    NoMission = 'You do not have an active cargo run.',
    NoAccess = 'Your current access level is too low for this location.',
    InvalidPin = 'That passcode was rejected.'
}
