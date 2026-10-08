Config = {}

-- CodeX Banking is written for QBCore + oxmysql. ox_lib, ox_target, qb-target and
-- ox_inventory are optional; the core bank UI and key prompts are self-contained.
Config.Debug = false
Config.Locale = 'en' -- This resource ships with an English-only interface.
Config.CurrencySymbol = '$'
Config.Database = {
    AutoCreate = true
}

-- Personal checking/savings accounts are mirrored to QBCore's player bank value
-- so existing server scripts that use Player.Functions.AddMoney/RemoveMoney keep
-- their usual semantics. Disable this only if you want a fully separate wallet.
Config.LegacySync = {
    Enabled = true
}

Config.Commands = {
    Bank = 'bank',
    ATM = 'atm',
    Admin = 'bankadmin'
}

Config.Interaction = {
    Key = 38, -- E
    KeyLabel = 'E',
    UseMarkers = true,
    MarkerDistance = 18.0,
    InteractDistance = 1.8,
    DrawDistance = 15.0,
    PromptDistance = 2.2,
    AutoCloseDistance = 13.0,
    ShowBlips = true
}

-- Each branch belongs to one of the three bank networks. Branch IDs are used for
-- server-side distance checks; edit/add entries for custom MLOs.
Config.Banks = {
    fleeca = {
        label = 'Fleeca Bank',
        prefix = 'FLC',
        color = '#49c5b6',
        openingFee = 0,
        branchWithdrawFee = 0,
        atmFee = 4,
        maxBalance = 10000000,
        defaultDailyLimit = 100000
    },
    maze = {
        label = 'Maze Bank',
        prefix = 'MZB',
        color = '#e45467',
        openingFee = 500,
        branchWithdrawFee = 0,
        atmFee = 3,
        maxBalance = 25000000,
        defaultDailyLimit = 250000
    },
    pacific = {
        label = 'Pacific Standard',
        prefix = 'PAC',
        color = '#e9b75e',
        openingFee = 1000,
        branchWithdrawFee = 0,
        atmFee = 0,
        maxBalance = 50000000,
        defaultDailyLimit = 500000
    }
}

Config.Branches = {
    { id = 'fleeca_cityhall', bank = 'fleeca', label = 'Fleeca — Legion Square', coords = vector3(149.05, -1041.30, 29.37), radius = 4.0 },
    { id = 'fleeca_missionrow', bank = 'fleeca', label = 'Fleeca — Mission Row', coords = vector3(313.32, -280.03, 54.17), radius = 4.0 },
    { id = 'fleeca_vinewood', bank = 'fleeca', label = 'Fleeca — Hawick', coords = vector3(-351.94, -50.72, 49.04), radius = 4.0 },
    { id = 'fleeca_delperro', bank = 'fleeca', label = 'Fleeca — Del Perro', coords = vector3(-1212.68, -331.83, 37.78), radius = 4.0 },
    { id = 'fleeca_burton', bank = 'fleeca', label = 'Fleeca — Rockford Hills', coords = vector3(-2961.67, 482.31, 15.70), radius = 4.0 },
    { id = 'fleeca_sandy', bank = 'fleeca', label = 'Fleeca — Sandy Shores', coords = vector3(1175.64, 2707.71, 38.09), radius = 4.0 },
    { id = 'pacific_downtown', bank = 'pacific', label = 'Pacific Standard — Downtown', coords = vector3(247.65, 223.87, 106.29), radius = 5.0 },
    { id = 'maze_tower', bank = 'maze', label = 'Maze Bank — Maze Bank Tower', coords = vector3(-75.0, -818.0, 326.2), radius = 5.0 },
    { id = 'fleeca_paleto', bank = 'fleeca', label = 'Fleeca — Paleto Bay', coords = vector3(-111.98, 6470.56, 31.63), radius = 4.0 }
}

Config.ATMs = {
    Enabled = true,
    Models = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' },
    -- A player may use an ATM near one of these points. Add custom/MLO ATM
    -- coordinates here. The client also checks for the real ATM prop model.
    AccessPoints = {
        vector3(158.80, -1015.21, 29.34),
        vector3(147.60, -1035.78, 29.34),
        vector3(119.10, -883.70, 31.12),
        vector3(-386.73, 6046.08, 31.50),
        vector3(-284.04, 6224.39, 31.19),
        vector3(-97.15, 6455.78, 31.46),
        vector3(174.78, 6637.85, 31.57),
        vector3(-132.14, 6366.57, 31.48),
        vector3(1138.23, -468.89, 66.73),
        vector3(296.46, -894.14, 29.23),
        vector3(-717.61, -915.65, 19.22),
        vector3(-821.64, -1081.91, 11.13),
        vector3(-526.64, -1222.97, 18.45),
        vector3(-256.20, -716.01, 33.53),
        vector3(-203.81, -861.37, 30.27),
        vector3(24.45, -946.00, 29.36),
        vector3(33.23, -1348.16, 29.50),
        vector3(289.01, -1256.80, 29.44),
        vector3(1686.75, 4815.81, 42.01),
        vector3(1701.21, 6426.57, 32.76),
        vector3(1822.66, 3683.10, 34.28),
        vector3(1968.07, 3743.57, 32.34),
        vector3(540.31, 2671.14, 42.16),
        vector3(2564.50, 2584.79, 38.08),
        vector3(2558.75, 351.01, 108.62),
        vector3(-1091.56, 2708.20, 18.95),
        vector3(-3144.13, 1127.42, 20.86),
        vector3(-3043.91, 594.89, 7.91),
        vector3(-1827.30, 784.88, 138.30)
    },
    InteractionRadius = 2.5,
    SessionRadius = 4.0,
    BasePrice = 250000,
    OwnerSurchargeMaxPercent = 3.0,
    OwnerFeeShare = 0.50,
    DefaultSurchargePercent = 0.0
}

Config.Transfer = {
    SameBankFeePercent = 0.0,
    InterBankFeePercent = 0.005, -- 0.5%, as in the reference feature list
    InterBankDailyCap = 5000000,
    MaxAmount = 5000000,
    MinAmount = 1,
    FeeGovernmentSharePercent = 1.0 -- 100% of network fees go to the bank/government vault
}

Config.Security = {
    SessionSeconds = 300,
    CardLockSeconds = 300,
    MaxCardPinAttempts = 3,
    MaxAmount = 10000000,
    ActionCooldownMs = 350,
    -- Set this server.cfg convar to a long random value. Used as the secret input
    -- when deriving PIN verifiers; the PIN itself is never sent back to the UI.
    PinSecretConvar = 'codex_banking:pinSecret',
    AdminAce = 'codex.banking.admin'
}

Config.Cards = {
    MaxPerCitizen = 5,
    Tiers = {
        standard = { label = 'Standard', issueCost = 0, dailyLimit = 15000, color = '#6f7b8f' },
        gold = { label = 'Gold', issueCost = 2500, dailyLimit = 50000, color = '#d4ad5c' },
        platinum = { label = 'Platinum', issueCost = 10000, dailyLimit = 150000, color = '#8cb3c8' },
        black = { label = 'Black', issueCost = 50000, dailyLimit = 500000, color = '#3a414b' }
    }
}

Config.Accounts = {
    MaxSharedAccounts = 5,
    MaxSharedMembers = 4,
    DefaultDailyLimit = 100000,
    DefaultMaxBalance = 10000000,
    UpgradeLevels = {
        [2] = { price = 5000, dailyLimit = 250000, maxBalance = 25000000 },
        [3] = { price = 20000, dailyLimit = 1000000, maxBalance = 100000000 }
    },
    Roles = {
        owner = { label = 'Owner', canWithdraw = true, canTransfer = true, canManage = true, dailyLimit = 10000000 },
        admin = { label = 'Admin', canWithdraw = true, canTransfer = true, canManage = true, dailyLimit = 500000 },
        member = { label = 'Member', canWithdraw = true, canTransfer = true, canManage = false, dailyLimit = 100000 },
        viewer = { label = 'Read-only', canWithdraw = false, canTransfer = false, canManage = false, dailyLimit = 0 }
    }
}

Config.Savings = {
    Enabled = true,
    RequiredOnlineSecondsPerDay = 3600,
    Tiers = {
        [1] = { label = 'Basic', interestPerPeriod = 0.0005, openingFee = 0 },
        [2] = { label = 'Plus', interestPerPeriod = 0.0025, openingFee = 5000 },
        [3] = { label = 'Premium', interestPerPeriod = 0.0075, openingFee = 15000 },
        [4] = { label = 'Elite', interestPerPeriod = 0.0150, openingFee = 50000 }
    }
}

Config.Loans = {
    Enabled = true,
    MaxActiveLoans = 2,
    LatePenaltyPercentPerDay = 0.01,
    DefaultAfterDaysLate = 14,
    SeizeVehicleOnDefault = true,
    VehicleTable = 'player_vehicles',
    BankVehicleCitizenId = 'codex_bank',
    CreditBands = {
        { min = 300, max = 399, rateAdjustment = 0.03 },
        { min = 400, max = 499, rateAdjustment = 0.02 },
        { min = 500, max = 599, rateAdjustment = 0.01 },
        { min = 600, max = 699, rateAdjustment = 0.00 },
        { min = 700, max = 799, rateAdjustment = -0.01 },
        { min = 800, max = 850, rateAdjustment = -0.03 }
    },
    Plans = {
        personal = { label = 'Personal loan', accountType = 'checking', minScore = 500, maxAmount = 50000, annualRate = 0.18, termDays = 14, requiresVehicle = false },
        secured = { label = 'Vehicle-secured loan', accountType = 'checking', minScore = 600, maxAmount = 250000, annualRate = 0.09, termDays = 30, requiresVehicle = true },
        business = { label = 'Business loan', accountType = 'company', minScore = 550, maxAmount = 500000, annualRate = 0.14, termDays = 30, requiresVehicle = false }
    }
}

Config.Invoices = {
    Enabled = true,
    ExpiryDays = 7,
    MaxAmount = 1000000,
    MaxReasonLength = 100
}

Config.Cheques = {
    Enabled = true,
    ExpiryDays = 7,
    MaxAmount = 1000000
}

Config.SafeBoxes = {
    Enabled = true,
    RentDays = 7,
    Tiers = {
        [10] = { label = '10 slots', price = 2500, slots = 10, maxWeight = 50000 },
        [30] = { label = '30 slots', price = 10000, slots = 30, maxWeight = 150000 }
    }
}

-- Configure which QBCore jobs get a CodeX company vault and who can use it.
-- These are a separate ledger. See the README for the optional qb-management bridge.
Config.JobAccounts = {
    police = { label = 'Los Santos Police Department', bank = 'fleeca', accessGrade = 0, withdrawGrade = 3, manageGrade = 4, dailyLimit = 1000000 },
    ambulance = { label = 'Pillbox Medical Services', bank = 'fleeca', accessGrade = 0, withdrawGrade = 2, manageGrade = 3, dailyLimit = 500000 },
    mechanic = { label = 'Benny’s Motorworks', bank = 'maze', accessGrade = 0, withdrawGrade = 2, manageGrade = 3, dailyLimit = 250000 }
}

Config.Admin = {
    QBCorePermissions = { 'admin', 'god' },
    MaxRuntimeTransferFeePercent = 5.0
}

Config.Messages = {
    interactBank = 'Press ~g~[E]~s~ to visit the bank',
    interactATM = 'Press ~g~[E]~s~ to use the ATM'
}
