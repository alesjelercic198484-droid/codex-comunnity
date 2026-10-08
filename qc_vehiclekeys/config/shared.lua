local Config = {}

-- QC Vehicle Keys Configuration
-- Configure this file to match your server setup

---@class Config.Settings
Config.Settings = {
    keepSteeringWheel = true,
    autoGiveKeys = true, -- Auto give keys when entering owned vehicles (garage/shop)
}

---@class Config.Locks
Config.Locks = {
    carEffect = true,
    playAnimation = 'advanced', -- 'simple' | 'advanced' | false
    keyBind = 'U',
    requireClosedDoors = true,
    canToggle = function()
        local playerState = LocalPlayer.state
        local stateBags = {'isDead', 'isCuffed', 'dead', 'inLastStand'}
        for _, state in ipairs(stateBags) do
            if playerState[state] then
                return false
            end
        end
        return true
    end,
    ignoreBikes = true,
    lockNpcVehicles = true,
    lockParkedVehicles = true,
    unlockToolJobs = {'mechanic', 'police'},
    findVehicleBlip = true,
}

---@class Config.Engine
Config.Engine = {
    preventDisable = true,
    keyBind = 'Y',
    ignoreBikes = true,
}

---@class Config.Theft
Config.Theft = {
    enabled = true,
    requiredItem = 'lockpick',
    removeItemOnFail = true,
    cooldown = 5000,
    alertPolice = true,
    policeAlertChance = 50,
    alarm = {
        enabled = true,
        onFail = {
            lockpick = true,
            hotwire = true,
            jammer = true,
        },
        onStartMinTier = 2,
        notifyOwner = true,
        duration = 30000,
    },
    difficulties = {
        easy = {
            pins = 3,
            timeLimit = 45000,
            tolerance = 15,
        },
        medium = {
            pins = 4,
            timeLimit = 35000,
            tolerance = 10,
        },
        hard = {
            pins = 5,
            timeLimit = 25000,
            tolerance = 6,
        },
        expert = {
            pins = 6,
            timeLimit = 20000,
            tolerance = 4,
        }
    },
    hotwireTimes = {
        easy = 35000,
        medium = 28000,
        hard = 22000,
        expert = 18000,
    },
    vehicleClassDifficulty = {
        [0] = 'easy',      -- Compacts
        [1] = 'easy',      -- Sedans
        [2] = 'medium',    -- SUVs
        [3] = 'medium',    -- Coupes
        [4] = 'medium',    -- Muscle
        [5] = 'hard',      -- Sports Classics
        [6] = 'hard',      -- Sports
        [7] = 'expert',    -- Super
        [8] = 'easy',      -- Motorcycles
        [9] = 'medium',    -- Off-road
        [10] = 'hard',     -- Industrial
        [11] = 'medium',   -- Utility
        [12] = 'easy',     -- Vans
        [13] = 'easy',     -- Cycles
        [14] = 'easy',     -- Boats
        [15] = 'hard',     -- Helicopters
        [16] = 'expert',   -- Planes
        [17] = 'hard',     -- Service
        [18] = 'expert',   -- Emergency
        [19] = 'expert',   -- Military
        [20] = 'hard',     -- Commercial
        [21] = 'easy',     -- Trains
    },
    blacklistedModels = {
        ['police'] = true,
        ['police2'] = true,
        ['police3'] = true,
        ['police4'] = true,
    },
    canAttempt = function(vehicle)
        local playerState = LocalPlayer.state
        local stateBags = {'isDead', 'isCuffed', 'dead', 'inLastStand'}
        for _, state in ipairs(stateBags) do
            if playerState[state] then
                return false
            end
        end
        return true
    end,
}

---@class Config.SecurityUpgrade
Config.SecurityUpgrade = {
    enabled = true,
    requiredJob = {'mechanic'},
    upgrades = {
        [1] = {
            label = 'Basic Security',
            requiredItem = 'security_chip_1',
            itemCount = 1,
            duration = 30000,
            nextTier = 2,
        },
        [2] = {
            label = 'Advanced Security',
            requiredItem = 'security_chip_2',
            itemCount = 1,
            duration = 35000,
            nextTier = 3,
        },
        [3] = {
            label = 'Expert Security',
            requiredItem = 'security_chip_3',
            itemCount = 1,
            duration = 40000,
            nextTier = nil,
        },
    }
}

return Config