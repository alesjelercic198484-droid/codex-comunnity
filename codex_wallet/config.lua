Config = {}

-- Enable extra prints in the server console.
Config.Debug = false

-- ---------------------------------------------------------------------------
-- Branding
-- ---------------------------------------------------------------------------
Config.Brand = {
    Name = 'CodeX Wallet',
    Tagline = 'Advanced secure wallet',
    Footer = 'CodeX Community • Premium Roleplay'
}

-- ---------------------------------------------------------------------------
-- Framework / inventory
-- ---------------------------------------------------------------------------
-- 'auto'  : use qb-core + qb-inventory, switch to ox_inventory adapters when
--           the ox_inventory resource is started.
-- 'qb'    : force the qb-inventory adapters.
-- 'ox'    : force the ox_inventory adapters.
Config.Inventory = 'auto'

-- Item name of the wallet (see install/qb_items.lua / install/ox_inventory_items.lua).
Config.WalletItem = 'codex_wallet'

-- ---------------------------------------------------------------------------
-- Wallet capacity
-- ---------------------------------------------------------------------------
Config.Wallet = {
    -- How many document/card items fit inside one wallet.
    Slots = 8,

    -- Total weight capacity of the wallet in grams (2000 g = 2.0 kg).
    MaxWeight = 2000,

    -- true  : the same item (e.g. two driver licences) cannot be stored twice.
    -- false : duplicates are allowed while slots remain.
    PreventDuplicates = true,

    -- Hard rule: a wallet can never be stored inside another wallet.
    PreventWalletInWallet = true
}

-- ---------------------------------------------------------------------------
-- Cash inside the wallet
-- ---------------------------------------------------------------------------
Config.Money = {
    Enabled = true,

    -- QBCore money account used for deposits / withdrawals.
    Account = 'cash',

    -- Minimum deposit / withdraw per operation.
    MinAmount = 1,

    -- Maximum deposit / withdraw per single operation (anti-dupe guard).
    MaxAmount = 250000,

    -- Maximum amount of cash one wallet can hold.
    MaxBalance = 1000000
}

-- ---------------------------------------------------------------------------
-- Whitelist: which inventory items may be stored inside the wallet
-- ---------------------------------------------------------------------------
-- Weight is in grams and is counted against Config.Wallet.MaxWeight.
Config.AllowedItems = {
    ['id_card'] = {
        label = 'ID Card',
        weight = 50,
        presentable = true
    },
    ['driver_license'] = {
        label = "Driver's License",
        weight = 50,
        presentable = true
    },
    ['weaponlicense'] = {
        label = 'Weapon License',
        weight = 50,
        presentable = true
    },
    ['government_id'] = {
        label = 'Government ID',
        weight = 50,
        presentable = true
    },
    ['dos_id_card'] = {
        label = 'DoS Secret Services ID',
        weight = 50,
        presentable = true
    }
}

-- ---------------------------------------------------------------------------
-- Commands / keybind
-- ---------------------------------------------------------------------------
-- Opens the wallet without needing the item in the inventory? No - the player
-- must still own a wallet item, this is only a shortcut for using it.
Config.Command = 'wallet'

-- Keybind command (RegisterKeyMapping). Set to false to disable.
Config.Keybind = {
    Enabled = true,
    Default = 'F7',
    Description = 'Open your CodeX Wallet'
}

-- Admin/testing command: gives a wallet, cash and sample ID cards.
-- Permission: QBCore admin/god permission or ACE 'codexwallet.admin'.
Config.AdminCommand = 'wallettest'

-- ---------------------------------------------------------------------------
-- Showing ID cards from the wallet to nearby players
-- ---------------------------------------------------------------------------
Config.Presentation = {
    Enabled = true,

    -- Radius (GTA units) scanned around the presenter.
    Radius = 4.0,

    -- How long (ms) the presented card stays on the viewer's screen.
    AutoCloseMs = 12000,

    -- false : only nearby players see the card.
    -- true  : the presenter also sees their own card popup.
    ShowOwnPopupToo = true
}

-- ---------------------------------------------------------------------------
-- Security
-- ---------------------------------------------------------------------------
Config.Security = {
    -- Minimum milliseconds between two wallet actions for one player.
    RateLimitMs = 250,

    -- Drop actions whose payload is larger than this (JSON) size in bytes.
    MaxPayloadSize = 8192
}

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------
-- Levels: 'DEBUG' < 'INFO' < 'WARN' < 'ERROR'
Config.Logging = {
    Level = 'INFO',

    -- Print to the server console.
    Console = true,

    -- Append to a log file inside the resource (logs/wallet.log).
    File = true,
    FileDir = 'logs',
    FileName = 'wallet.log',

    -- Discord webhook URL. Leave empty to disable.
    -- Can also be set with the convar:  set codex_wallet:webhook "https://..."
    Webhook = '',
    WebhookName = 'CodeX Wallet Logs'
}

-- ---------------------------------------------------------------------------
-- Notifications (plain strings so they are easy to translate)
-- ---------------------------------------------------------------------------
Config.Notifications = {
    NoWallet = 'You do not have a wallet.',
    NotReady = 'Your wallet is still loading, try again in a second.',
    NoPermission = 'You are not allowed to do that.',
    Deposited = 'You deposited $%s into your wallet.',
    Withdrew = 'You withdrew $%s from your wallet.',
    NotEnoughCash = 'You do not have that much cash.',
    NotEnoughWalletCash = 'There is not that much cash in the wallet.',
    InvalidAmount = 'Invalid amount.',
    AmountTooHigh = 'That amount is too high for a single operation.',
    WalletFull = 'Your wallet is full.',
    WalletTooHeavy = 'Your wallet cannot hold any more weight.',
    ItemNotAllowed = 'That item cannot be stored in the wallet.',
    AlreadyStored = 'That item is already inside the wallet.',
    WalletInWallet = 'You cannot store a wallet inside another wallet.',
    Stored = 'You stored %s in your wallet.',
    Removed = 'You took %s out of your wallet.',
    NoRoomInventory = 'You do not have enough space in your inventory.',
    NothingToStore = 'You have nothing that can be stored in your wallet.',
    Presented = 'You showed your %s.',
    ReceivedCard = '%s showed you their %s.',
    Cooldown = 'Slow down a little.'
}
