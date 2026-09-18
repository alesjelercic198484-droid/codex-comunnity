Config = {}

Config.Debug = false
Config.JobName = 'gouv'
Config.JobLabel = 'United States Government'

-- These mirror the requested ESX grades. The SQL installer creates them.
Config.Ranks = {
    [0] = { name = 'judge',          label = 'Judge' },
    [1] = { name = 'prosecutor',     label = 'Prosecutor' },
    [2] = { name = 'governor',       label = 'Governor' },
    [3] = { name = 'president',      label = 'President' },
    [4] = { name = 'secret service', label = 'Secret Services' },
    [5] = { name = 'us marshal',     label = 'US Marshal' }
}

Config.Armory = {
    Enabled = true,
    ShopId = 'codex_government_armory',
    Label = 'City Hall Government Armory',

    -- Default GTA V City Hall exterior. Move this point into your City Hall MLO.
    Coords = vector3(-545.38, -204.03, 38.22),
    Size = vector3(1.5, 1.5, 2.2),
    Rotation = 30.0,
    TargetDistance = 2.0,
    DrawTargetSprite = true,
    DebugZone = false,

    -- true: every gouv rank (grade 0+) can obtain every configured police item.
    -- false: the individual `grade` values in Items are enforced.
    AllowAllItemsForGovernment = true,

    -- All official p_policejob armory items plus a full standard loadout.
    -- Items that are not registered in ox_inventory are skipped safely and
    -- listed in the server console instead of breaking the whole shop.
    Items = {
        { name = 'government_id',         price = 0, grade = 0 },
        { name = 'spike_strip',           price = 0, grade = 0 },
        { name = 'police_diving_suit',    price = 0, grade = 0 },
        { name = 'tracking_band',         price = 0, grade = 0 },
        { name = 'fingerprinter',         price = 0, grade = 0 },
        { name = 'stick_bag',             price = 0, grade = 0 },
        { name = 'stick',                 price = 0, grade = 0 },
        { name = 'body_cam',              price = 0, grade = 0 },
        { name = 'gps',                   price = 0, grade = 0 },
        { name = 'camera',                price = 0, grade = 0 },
        { name = 'radio',                 price = 0, grade = 0 },
        { name = 'handcuffs',             price = 0, grade = 0 },
        { name = 'vest_normal',           price = 0, grade = 0 },
        { name = 'vest_strong',           price = 0, grade = 2 },
        { name = 'ammo-9',                price = 0, grade = 1 },
        { name = 'ammo-shotgun',          price = 0, grade = 4 },
        { name = 'ammo-rifle',            price = 0, grade = 5 },
        { name = 'WEAPON_FLASHLIGHT',     price = 0, grade = 0 },
        { name = 'WEAPON_NIGHTSTICK',     price = 0, grade = 1, metadata = { registered = true } },
        { name = 'WEAPON_STUNGUN',        price = 0, grade = 1, metadata = { registered = true } },
        { name = 'WEAPON_COMBATPISTOL',   price = 0, grade = 2, metadata = { registered = true } },
        { name = 'WEAPON_PUMPSHOTGUN',    price = 0, grade = 4, metadata = { registered = true } },
        { name = 'WEAPON_CARBINERIFLE',   price = 0, grade = 5, metadata = { registered = true } }
    }
}

Config.WeaponSerials = {
    Enabled = true,
    Prefix = 'GOV',

    -- Every weapon issued by the City Hall armory receives a unique serial in
    -- the form GOV-XXXXXXXX-XXXXXX. Non-gun equipment is excluded below.
    ExcludedItems = {
        WEAPON_FLASHLIGHT = true,
        WEAPON_NIGHTSTICK = true
    },

    -- Also convert matching firearms already held by a gouv player when this
    -- resource starts, when the player loads, or when their job becomes gouv.
    UpdateExistingGovernmentWeapons = true,

    -- Internal one-use marker. Do not use this metadata key in other scripts.
    PendingMetadataKey = '_codexGovernmentSerial'
}

Config.Identification = {
    Item = 'government_id',
    Agency = 'UNITED STATES GOVERNMENT',
    Department = 'EXECUTIVE & JUDICIAL AUTHORITY',
    Authority = 'CITY OF LOS SANTOS',
    Footer = 'This credential identifies an authorized government official. Tampering, duplication, or unauthorized possession is prohibited.',
    PresentRadius = 5.0,
    AutoCloseMs = 12000,

    -- Using the inventory item shows it to every nearby player. This target
    -- option also lets the holder deliberately present it to one player.
    EnablePlayerTarget = true,
    ShowToAllNearbyOnUse = true
}

Config.Tracking = {
    Enabled = true,
    -- Only gouv sees these blips. Positions are assembled server-side and are
    -- never broadcast to ordinary clients.
    RefreshMs = 2000,
    ExpireMs = 6500,
    FlashIntervalMs = 900,
    ShowPlayerNames = true,
    Jobs = {
        police = {
            label = 'Police Unit',
            sprite = 1,
            colour = 3,
            scale = 0.82
        },
        ambulance = {
            label = 'EMS Unit',
            sprite = 153,
            colour = 1,
            scale = 0.82
        }
    }
}

Config.CuffProtection = {
    Enabled = true,
    StateKey = 'codexGovernmentProtected',
    PoliceJobs = {
        police = true
    },
    MaxDistance = 4.0,
    TaseAttacker = true,
    TaseDurationMs = 5000,
    AttemptCooldownMs = 5000,

    -- Repairs native/state-bag cuff state if another resource ignores the
    -- CanCuff export. For guaranteed p_policejob prevention, apply the small
    -- integration guard included in install/P_POLICEJOB_INTEGRATION.md.
    ClientSafetyNet = true
}

Config.Notifications = {
    Title = 'Government Services',
    NotGovernment = 'This service is restricted to authorized government personnel.',
    MissingId = 'You do not have your Government ID.',
    NoPlayer = 'No valid player was found nearby.',
    IdPresented = 'Government ID presented.',
    IdReceived = '%s presented a Government ID.',
    CuffBlockedOfficer = 'Cuff attempt denied: this government official has protected status.',
    CuffBlockedOfficial = 'An unauthorized restraint attempt was blocked.',
    SafetyReleased = 'Government protection removed an unauthorized restraint.',
    ArmoryUnavailable = 'The government armory is currently unavailable.'
}
