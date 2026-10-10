--[[----------------------------------------------------------------------------
    CodeX Roleplay Inventory - configuration

    Drop-in replacement for `qb-inventory`. The resource keeps the stock
    qb-core data model (items live in `PlayerData.items`, keyed by slot number)
    so every other qb-core script keeps working without any change.

    All comments and all in-game text are in English.
----------------------------------------------------------------------------]]

Config = {}

-- Header shown ABOVE the inventory. Change this to rebrand the UI.
Config.Brand = {
    Text = 'CodeX Roleplay',
    SubText = 'Inventory',
    -- Optional logo rendered left of the brand text (put it in html/images/).
    -- Leave empty to only render the text.
    Logo = '',
    -- Show the live player count / server id chip next to the brand.
    ShowPlayerChip = true
}

-- Inventory size and weight -------------------------------------------------
Config.MaxSlots = 40          -- qb-inventory default: slots 1..40
Config.MaxWeight = 120000     -- grams (120 kg), qb-inventory default
Config.HotbarSlots = 5        -- slots 1..5 are the hotbar (keys 1-5)

-- Keys ---------------------------------------------------------------------
Config.Keys = {
    Open = 'TAB',           -- open / close the inventory
    UseHotbar = {},         -- keys 1..5 are handled by number keys
    Close = 'ESCAPE'
}

-- Item images ---------------------------------------------------------------
Config.Images = {
    -- Where item icons are loaded from. `.png` files live in html/images/.
    Path = 'images/',
    Extension = '.png',
    -- When an item has no image, render a generated tile with its initials.
    Fallback = true
}

-- Rarity -------------------------------------------------------------------
-- Rarity is resolved per item name. `Config.Rarity.Items` wins, then the
-- `rarity` field inside QBCore.Shared.Items, then `Config.Rarity.Default`.
-- Tiers: common, uncommon, rare, epic, legendary, mythic
Config.Rarity = {
    Enabled = true,
    Default = 'common',
    -- High tiers get the "breathing" aura and a stronger outline.
    AuraTiers = { legendary = true, mythic = true },
    Items = {
        -- ['lockpick'] = 'uncommon',
        -- ['weapon_pistol'] = 'rare',
        -- ['goldbar'] = 'legendary',
    },
    -- Money items are always rendered with the cash styling.
    Money = { money = true, black_money = true, markedbills = true }
}

-- Sounds (synthesised with the WebAudio API - no audio files needed) --------
Config.Sounds = {
    Enabled = true,
    Volume = 0.35,
    Events = {
        open    = true,
        close   = true,
        pickup  = true,
        drop    = true,
        use     = true,
        move    = true,
        error   = true
    }
}

-- Toasts (pickup / drop / use / equip popups) -------------------------------
Config.Toasts = {
    Enabled = true,
    Duration = 2600,
    Max = 4
}

-- Defaults for the in-game settings studio. Players can change everything
-- live; these values are only used until a player saves his own profile.
Config.Defaults = {
    Layout = 'showcase',   -- showcase | classic | grid | tarkov
    Theme = 'glass',       -- glass | tactical | neon | minimal | luxe
    Accent = 'emerald',    -- see html/app.js ACCENTS (17 accents)
    CustomAccent = '',     -- hex colour picked with the colour picker

    SlotStyle = 'rounded', -- rounded | sharp | soft | outline | float
    IconShape = 'squircle',-- squircle | square | circle | hexagon | diamond | leaf | shield | blob
    Font = 'modern',       -- modern | condensed | mono | display
    BadgeLayout = 'stack', -- stack | inline | corner | pill | minimal
    WeightBar = 'segment', -- bar | segment | ring | minimal
    Reveal = 'rise',       -- rise | fade | scale | none

    RarityStyle = 'wash',  -- wash | outline | both | off
    Animations = true,
    ReducedMotion = false,
    Sounds = true,
    PedPreview = true,
    CursorTrail = true,

    Language = 'en'        -- en | pt | es | fr | de | it | sl
}

-- Localisation --------------------------------------------------------------
Config.Locale = 'en'
Config.AvailableLocales = { 'en', 'pt', 'es', 'fr', 'de', 'it', 'sl' }

-- Permissions ---------------------------------------------------------------
Config.Permissions = {
    -- Anybody with this ace may push the look + texts to the whole server.
    AdminLock = 'inventory.admin',
    -- Anybody may open the settings studio for himself:
    SettingsStudio = true
}

-- Drops (items thrown on the ground) ----------------------------------------
Config.Drops = {
    Enabled = true,
    -- How close (metres) a player has to stand to interact with a drop.
    InteractRange = 2.0,
    -- How far away drops are still drawn as markers.
    DrawRange = 25.0,
    -- Minutes before an untouched drop despawns (0 = never).
    DespawnTime = 0,
    Slots = 10,
    MaxWeight = 1000000
}

-- Stashes -------------------------------------------------------------------
Config.Stashes = {
    -- Persist stashes into SQL. If the table is missing the resource logs one
    -- warning and keeps everything in memory, so it never hard-fails.
    Persist = true,
    Table = 'codex_inventories',
    DefaultSlots = 50,
    DefaultMaxWeight = 1000000
}

-- Vehicles ------------------------------------------------------------------
Config.Vehicles = {
    Glovebox = { Slots = 5,  MaxWeight = 10000 },
    Trunk = {
        -- Weight per vehicle class, fallback first.
        Default = { Slots = 50, MaxWeight = 60000 },
        ClassOverrides = {
            -- [0] = { Slots = 50, MaxWeight = 60000 },   -- compacts
        }
    }
}

-- Other players (search / rob) ----------------------------------------------
Config.OtherPlayer = {
    Enabled = true,
    Range = 2.5
}

-- Shops (used by qb-shops and by custom scripts) ----------------------------
Config.Shops = {
    Enabled = true
}

-- Items sold by vending machines (prop_vend_*) ------------------------------
Config.VendingItems = {
    { name = 'water_bottle', price = 4, amount = 50 },
    { name = 'kurkakola',    price = 4, amount = 50 },
    { name = 'sandwich',     price = 6, amount = 25 }
}

-- Debug ----------------------------------------------------------------------
Config.Debug = false
