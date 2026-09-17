local RESOURCE = GetCurrentResourceName()

local ESX = nil
local DatabaseDriver = nil
local DatabaseReady = false
local CallbacksRegistered = false

local PlayerStates = {}
local ClaimLocks = {}

local function DebugPrint(...)
    if Config.Debug then
        print(('[%s]'):format(RESOURCE), ...)
    end
end

local function SafeTableName()
    local name = tostring((Config.Database and Config.Database.Table) or 'codex_daily_missions')
    if not name:match('^[%w_]+$') then
        print(('[%s] Invalid table name in config.lua, falling back to codex_daily_missions.'):format(RESOURCE))
        name = 'codex_daily_missions'
    end
    return ('`%s`'):format(name)
end

local TABLE_NAME = SafeTableName()

local function ToNumber(value, fallback)
    local number = tonumber(value)
    if number == nil then
        return fallback or 0
    end
    return number
end

local function ToBoolean(value)
    return value == true or value == 1 or value == '1' or value == 'true'
end

local function TryGetESX()
    if ESX then
        return ESX
    end

    if Config.ESX and Config.ESX.UseExport ~= false then
        local exportName = Config.ESX.ExportName or 'es_extended'
        local ok, object = pcall(function()
            return exports[exportName]:getSharedObject()
        end)

        if ok and object then
            ESX = object
            return ESX
        end
    end

    TriggerEvent((Config.ESX and Config.ESX.SharedObjectEvent) or 'esx:getSharedObject', function(object)
        ESX = object
    end)

    return ESX
end

local function IsResourceStarted(resourceName)
    local state = GetResourceState(resourceName)
    return state == 'started'
end

local function DetectDatabaseDriver()
    local configured = (Config.Database and Config.Database.Driver) or 'auto'

    if configured ~= 'auto' then
        return configured
    end

    if IsResourceStarted('oxmysql') then
        return 'oxmysql'
    end

    if IsResourceStarted('mysql-async') or (MySQL and MySQL.Async) then
        return 'mysql-async'
    end

    if IsResourceStarted('ghmattimysql') then
        return 'ghmattimysql'
    end

    return nil
end

local function IsDriverReady(driver)
    if driver == 'oxmysql' then
        return IsResourceStarted('oxmysql')
    end

    if driver == 'mysql-async' then
        return (MySQL and MySQL.Async) ~= nil or IsResourceStarted('mysql-async')
    end

    if driver == 'ghmattimysql' then
        return IsResourceStarted('ghmattimysql')
    end

    return false
end

local function ConvertNamedParameters(query, parameters)
    local orderedParameters = {}
    local convertedQuery = query:gsub('@([%w_]+)', function(parameterName)
        local value = nil

        if parameters then
            value = parameters['@' .. parameterName]
            if value == nil then
                value = parameters[parameterName]
            end
        end

        orderedParameters[#orderedParameters + 1] = value
        return '?'
    end)

    return convertedQuery, orderedParameters
end

local function ResolvePromiseSafely(promiseObject, result)
    promiseObject:resolve(result or {})
end

local function DBFetch(query, parameters)
    if not DatabaseDriver then
        print(('[%s] Database query attempted before a database driver was ready.'):format(RESOURCE))
        return {}
    end

    local promiseObject = promise.new()
    local resolved = false

    local function finish(result)
        if resolved then
            return
        end
        resolved = true
        ResolvePromiseSafely(promiseObject, result)
    end

    local ok, errorMessage = pcall(function()
        if DatabaseDriver == 'oxmysql' then
            local convertedQuery, orderedParameters = ConvertNamedParameters(query, parameters)
            exports.oxmysql:query(convertedQuery, orderedParameters, finish)
        elseif DatabaseDriver == 'mysql-async' then
            MySQL.Async.fetchAll(query, parameters or {}, finish)
        elseif DatabaseDriver == 'ghmattimysql' then
            exports.ghmattimysql:execute(query, parameters or {}, finish)
        else
            finish({})
        end
    end)

    if not ok then
        print(('[%s] Database fetch failed: %s'):format(RESOURCE, errorMessage))
        finish({})
    end

    return Citizen.Await(promiseObject) or {}
end

local function DBExecute(query, parameters)
    if not DatabaseDriver then
        print(('[%s] Database execute attempted before a database driver was ready.'):format(RESOURCE))
        return nil
    end

    local promiseObject = promise.new()
    local resolved = false

    local function finish(result)
        if resolved then
            return
        end
        resolved = true
        ResolvePromiseSafely(promiseObject, result)
    end

    local ok, errorMessage = pcall(function()
        if DatabaseDriver == 'oxmysql' then
            local convertedQuery, orderedParameters = ConvertNamedParameters(query, parameters)
            exports.oxmysql:query(convertedQuery, orderedParameters, finish)
        elseif DatabaseDriver == 'mysql-async' then
            MySQL.Async.execute(query, parameters or {}, finish)
        elseif DatabaseDriver == 'ghmattimysql' then
            exports.ghmattimysql:execute(query, parameters or {}, finish)
        else
            finish(nil)
        end
    end)

    if not ok then
        print(('[%s] Database execute failed: %s'):format(RESOURCE, errorMessage))
        finish(nil)
    end

    return Citizen.Await(promiseObject)
end

local function CreateDatabaseTable()
    local createQuery = ([[
        CREATE TABLE IF NOT EXISTS %s (
          `identifier` varchar(80) NOT NULL,
          `day_key` varchar(32) NOT NULL,
          `mission_key` varchar(64) NOT NULL,
          `label` varchar(128) DEFAULT NULL,
          `description` varchar(255) DEFAULT NULL,
          `required_seconds` int unsigned NOT NULL DEFAULT 0,
          `progress` int unsigned NOT NULL DEFAULT 0,
          `completed` tinyint(1) NOT NULL DEFAULT 0,
          `claimed` tinyint(1) NOT NULL DEFAULT 0,
          `rewards_json` longtext DEFAULT NULL,
          `completed_at` timestamp NULL DEFAULT NULL,
          `claimed_at` timestamp NULL DEFAULT NULL,
          `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`identifier`, `day_key`, `mission_key`),
          KEY `idx_codex_daily_identifier_claimed` (`identifier`, `claimed`),
          KEY `idx_codex_daily_day` (`day_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]]):format(TABLE_NAME)

    DBExecute(createQuery)
end

local function CloneSerializable(value)
    if type(value) ~= 'table' then
        return value
    end

    local output = {}
    for key, nestedValue in pairs(value) do
        local nestedType = type(nestedValue)
        if nestedType == 'string' or nestedType == 'number' or nestedType == 'boolean' or nestedType == 'table' then
            output[key] = CloneSerializable(nestedValue)
        end
    end

    return output
end

local MissionConfigByKey = nil

local function RebuildMissionMap()
    local map = {}

    for index, mission in ipairs(Config.Missions or {}) do
        if mission.key then
            mission.order = index
            map[mission.key] = mission
        end
    end

    MissionConfigByKey = map
end

local function GetMissionConfig(missionKey)
    if not MissionConfigByKey then
        RebuildMissionMap()
    end

    return MissionConfigByKey[missionKey]
end

local function EncodeRewards(rewards)
    local ok, encoded = pcall(json.encode, CloneSerializable(rewards or {}))
    if ok then
        return encoded
    end

    return '[]'
end

local function DecodeRewards(row)
    local rawRewards = row and row.rewards_json

    if not rawRewards or rawRewards == '' then
        local mission = row and GetMissionConfig(row.mission_key)
        return CloneSerializable((mission and mission.rewards) or {})
    end

    local ok, decoded = pcall(json.decode, rawRewards)
    if ok and type(decoded) == 'table' then
        return decoded
    end

    return {}
end

local function GetDayKey(timestamp)
    local resetHour = ToNumber(Config.Reset and Config.Reset.Hour, 0) % 24
    local adjustedTimestamp = (timestamp or os.time()) - (resetHour * 3600)

    if Config.Reset and Config.Reset.Timezone == 'utc' then
        return os.date('!%Y-%m-%d', adjustedTimestamp)
    end

    return os.date('%Y-%m-%d', adjustedTimestamp)
end

local function SecondsUntilNextReset()
    local now = os.time()
    local currentDay = GetDayKey(now)

    for seconds = 60, 90000, 60 do
        if GetDayKey(now + seconds) ~= currentDay then
            return seconds
        end
    end

    return 86400
end

local function Notify(source, message, notificationType)
    TriggerClientEvent(RESOURCE .. ':notify', source, message, notificationType or 'info')
end

local function InsertMissingMissionRow(identifier, dayKey, mission)
    local rewardsJson = EncodeRewards(mission.rewards)
    local requiredSeconds = math.max(0, math.floor(ToNumber(mission.requiredSeconds, 0)))

    DBExecute(([[
        INSERT IGNORE INTO %s
        (`identifier`, `day_key`, `mission_key`, `label`, `description`, `required_seconds`, `progress`, `completed`, `claimed`, `rewards_json`)
        VALUES (@identifier, @day_key, @mission_key, @label, @description, @required_seconds, 0, @completed, 0, @rewards_json)
    ]]):format(TABLE_NAME), {
        ['@identifier'] = identifier,
        ['@day_key'] = dayKey,
        ['@mission_key'] = mission.key,
        ['@label'] = mission.label or mission.key,
        ['@description'] = mission.description or '',
        ['@required_seconds'] = requiredSeconds,
        ['@completed'] = requiredSeconds <= 0 and 1 or 0,
        ['@rewards_json'] = rewardsJson
    })

    return {
        identifier = identifier,
        day_key = dayKey,
        mission_key = mission.key,
        label = mission.label or mission.key,
        description = mission.description or '',
        required_seconds = requiredSeconds,
        progress = requiredSeconds <= 0 and requiredSeconds or 0,
        completed = requiredSeconds <= 0 and 1 or 0,
        claimed = 0,
        rewards_json = rewardsJson
    }
end

local function RowToMission(row, dayKey)
    local missionKey = row.mission_key
    local configuredMission = GetMissionConfig(missionKey) or {}
    local requiredSeconds = math.max(0, math.floor(ToNumber(row.required_seconds, configuredMission.requiredSeconds or 0)))
    local progress = math.max(0, math.floor(ToNumber(row.progress, 0)))

    if requiredSeconds > 0 then
        progress = math.min(progress, requiredSeconds)
    end

    local completed = ToBoolean(row.completed) or requiredSeconds <= 0 or (requiredSeconds > 0 and progress >= requiredSeconds)

    return {
        dayKey = row.day_key or dayKey,
        key = missionKey,
        label = row.label or configuredMission.label or missionKey,
        description = row.description or configuredMission.description or '',
        requiredSeconds = requiredSeconds,
        progress = completed and requiredSeconds or progress,
        completed = completed,
        claimed = ToBoolean(row.claimed),
        rewards = DecodeRewards(row),
        icon = configuredMission.icon or 'gift',
        order = configuredMission.order or 9999,
        dirty = false
    }
end

local function GetPlayerIdentifier(source, xPlayer)
    xPlayer = xPlayer or (ESX and ESX.GetPlayerFromId(source))
    if not xPlayer then
        return nil
    end

    return xPlayer.identifier
end

local function LoadPlayer(source, xPlayer)
    if not DatabaseReady then
        return nil
    end

    xPlayer = xPlayer or ESX.GetPlayerFromId(source)
    local identifier = GetPlayerIdentifier(source, xPlayer)

    if not identifier then
        return nil
    end

    local dayKey = GetDayKey()
    local rows = DBFetch(([[
        SELECT * FROM %s
        WHERE identifier = @identifier
        AND (day_key = @day_key OR (completed = 1 AND claimed = 0))
        ORDER BY created_at ASC
    ]]):format(TABLE_NAME), {
        ['@identifier'] = identifier,
        ['@day_key'] = dayKey
    })

    local currentRowsByKey = {}
    local oldUnclaimedRows = {}

    for _, row in ipairs(rows or {}) do
        if row.day_key == dayKey then
            currentRowsByKey[row.mission_key] = row
        elseif ToBoolean(row.completed) and not ToBoolean(row.claimed) then
            oldUnclaimedRows[#oldUnclaimedRows + 1] = row
        end
    end

    local missions = {}

    for index, mission in ipairs(Config.Missions or {}) do
        if mission.key then
            local row = currentRowsByKey[mission.key]
            if not row then
                row = InsertMissingMissionRow(identifier, dayKey, mission)
            end

            local missionState = RowToMission(row, dayKey)
            missionState.order = index
            missions[mission.key] = missionState
        end
    end

    local unclaimed = {}

    for _, row in ipairs(oldUnclaimedRows) do
        local missionState = RowToMission(row, row.day_key)
        if missionState.completed and not missionState.claimed then
            unclaimed[missionState.dayKey .. ':' .. missionState.key] = missionState
        end
    end

    local now = os.time()
    PlayerStates[source] = {
        source = source,
        identifier = identifier,
        dayKey = dayKey,
        missions = missions,
        unclaimed = unclaimed,
        lastProgressAt = now,
        nextSaveAt = now + ToNumber(Config.Progress and Config.Progress.SaveIntervalSeconds, 120),
        lastHeartbeatAt = now,
        clientActive = true
    }

    DebugPrint(('Loaded %s (%s)'):format(GetPlayerName(source) or tostring(source), identifier))
    return PlayerStates[source]
end

local function SavePlayer(source, force)
    local state = PlayerStates[source]
    if not state or not DatabaseReady then
        return
    end

    for _, mission in pairs(state.missions or {}) do
        if force or mission.dirty then
            DBExecute(([[
                UPDATE %s
                SET progress = @progress,
                    completed = @completed,
                    completed_at = CASE WHEN @completed = 1 AND completed_at IS NULL THEN CURRENT_TIMESTAMP ELSE completed_at END,
                    updated_at = CURRENT_TIMESTAMP
                WHERE identifier = @identifier AND day_key = @day_key AND mission_key = @mission_key
            ]]):format(TABLE_NAME), {
                ['@identifier'] = state.identifier,
                ['@day_key'] = mission.dayKey,
                ['@mission_key'] = mission.key,
                ['@progress'] = math.max(0, math.floor(ToNumber(mission.progress, 0))),
                ['@completed'] = mission.completed and 1 or 0
            })

            mission.dirty = false
        end
    end
end

local function EnsurePlayerLoaded(source)
    if PlayerStates[source] then
        return PlayerStates[source]
    end

    return LoadPlayer(source)
end

local function IsProgressAllowed(state)
    if not Config.Progress or not Config.Progress.RequireClientHeartbeat then
        return true
    end

    local timeout = ToNumber(Config.Progress.HeartbeatTimeoutSeconds, 150)
    return state.clientActive and (os.time() - ToNumber(state.lastHeartbeatAt, 0)) <= timeout
end

local function GetCountingMap(state)
    local counting = {}
    local mode = (Config.Progress and Config.Progress.Mode) or 'all'

    if mode == 'sequential' then
        for _, configuredMission in ipairs(Config.Missions or {}) do
            local mission = configuredMission.key and state.missions[configuredMission.key]
            if mission and not mission.completed and not mission.claimed then
                counting[mission.key] = true
                break
            end
        end
    else
        for key, mission in pairs(state.missions or {}) do
            if not mission.completed and not mission.claimed then
                counting[key] = true
            end
        end
    end

    return counting
end

local function BuildPublicState(source)
    local state = PlayerStates[source]
    if not state then
        return {
            ok = false,
            error = Config.Notifications and Config.Notifications.NotReady or 'Daily mission data is not ready.'
        }
    end

    local countingMap = GetCountingMap(state)
    local missions = {}
    local unclaimed = {}
    local counts = {
        total = 0,
        completed = 0,
        claimed = 0,
        claimable = 0,
        oldClaimable = 0
    }

    local function toPublicMission(mission)
        local requiredSeconds = math.max(0, math.floor(ToNumber(mission.requiredSeconds, 0)))
        local progress = math.max(0, math.floor(ToNumber(mission.progress, 0)))

        if requiredSeconds > 0 then
            progress = math.min(progress, requiredSeconds)
        end

        local completed = mission.completed or requiredSeconds <= 0 or (requiredSeconds > 0 and progress >= requiredSeconds)
        local claimed = mission.claimed == true

        return {
            dayKey = mission.dayKey,
            key = mission.key,
            label = mission.label,
            description = mission.description,
            requiredSeconds = requiredSeconds,
            progress = completed and requiredSeconds or progress,
            completed = completed,
            claimed = claimed,
            canClaim = completed and not claimed,
            rewards = mission.rewards or {},
            icon = mission.icon or 'gift',
            order = mission.order or 9999,
            isCounting = countingMap[mission.key] == true and not completed and not claimed
        }
    end

    for _, mission in pairs(state.missions or {}) do
        local publicMission = toPublicMission(mission)
        missions[#missions + 1] = publicMission

        counts.total = counts.total + 1
        if publicMission.completed then
            counts.completed = counts.completed + 1
        end
        if publicMission.claimed then
            counts.claimed = counts.claimed + 1
        end
        if publicMission.canClaim then
            counts.claimable = counts.claimable + 1
        end
    end

    table.sort(missions, function(a, b)
        return (a.order or 9999) < (b.order or 9999)
    end)

    for _, mission in pairs(state.unclaimed or {}) do
        local publicMission = toPublicMission(mission)
        unclaimed[#unclaimed + 1] = publicMission
        if publicMission.canClaim then
            counts.oldClaimable = counts.oldClaimable + 1
        end
    end

    table.sort(unclaimed, function(a, b)
        if a.dayKey == b.dayKey then
            return (a.order or 9999) < (b.order or 9999)
        end
        return tostring(a.dayKey) < tostring(b.dayKey)
    end)

    return {
        ok = true,
        resource = RESOURCE,
        title = Config.UI and Config.UI.Title or 'Daily Missions',
        subtitle = Config.UI and Config.UI.Subtitle or '',
        accentColor = Config.UI and Config.UI.AccentColor or '#26f3c9',
        dayKey = state.dayKey,
        resetInSeconds = SecondsUntilNextReset(),
        progressMode = (Config.Progress and Config.Progress.Mode) or 'all',
        missions = missions,
        unclaimed = unclaimed,
        counts = counts
    }
end

local function FormatRewardLabel(reward)
    if reward.label then
        return reward.label
    end

    local rewardType = tostring(reward.type or ''):lower()
    local amount = ToNumber(reward.amount or reward.count, 0)

    if rewardType == 'money' or rewardType == 'cash' then
        return ('$%s Cash'):format(amount)
    elseif rewardType == 'bank' then
        return ('$%s Bank'):format(amount)
    elseif rewardType == 'account' then
        return ('%s %s'):format(amount, reward.account or 'account')
    elseif rewardType == 'item' then
        return ('%s x%s'):format(reward.name or 'item', ToNumber(reward.count or reward.amount, 1))
    elseif rewardType == 'weapon' then
        return reward.name or 'Weapon'
    elseif rewardType == 'vehicle' then
        return reward.model or reward.name or 'Vehicle'
    elseif rewardType == 'command' then
        return 'Custom reward'
    end

    return 'Reward'
end

local function UsesOxInventory()
    return Config.Inventory
        and Config.Inventory.Type == 'ox_inventory'
        and GetResourceState('ox_inventory') == 'started'
end

local function AllowInventoryFallback()
    return not Config.Inventory or Config.Inventory.AllowESXFallback ~= false
end

local function BuildWeaponMetadata(reward)
    local metadata = {}

    if type(reward.metadata) == 'table' then
        for key, value in pairs(reward.metadata) do
            metadata[key] = value
        end
    end

    if reward.ammo ~= nil and metadata.ammo == nil then
        metadata.ammo = math.max(0, math.floor(ToNumber(reward.ammo, 0)))
    end

    return metadata
end

local function OxCanCarry(source, itemName, count, metadata)
    if not UsesOxInventory() then
        return nil
    end

    local ok, result = pcall(function()
        return exports.ox_inventory:CanCarryItem(source, itemName, count, metadata)
    end)

    if not ok then
        print(('[%s] ox_inventory CanCarryItem failed for %s: %s'):format(RESOURCE, tostring(itemName), tostring(result)))
        return false, Config.Notifications.NoInventorySpace
    end

    return result == true
end

local function OxItemCount(source, itemName, metadata)
    if not UsesOxInventory() then
        return 0
    end

    local ok, result = pcall(function()
        return exports.ox_inventory:Search(source, 'count', itemName, metadata)
    end)

    if not ok then
        print(('[%s] ox_inventory Search failed for %s: %s'):format(RESOURCE, tostring(itemName), tostring(result)))
        return 0
    end

    if type(result) == 'number' then
        return result
    end

    if type(result) == 'table' then
        return ToNumber(result[itemName], 0)
    end

    return 0
end

local function OxAddItem(source, itemName, count, metadata)
    if not UsesOxInventory() then
        return nil
    end

    local ok, success, response = pcall(function()
        return exports.ox_inventory:AddItem(source, itemName, count, metadata)
    end)

    if not ok then
        print(('[%s] ox_inventory AddItem failed for %s: %s'):format(RESOURCE, tostring(itemName), tostring(success)))
        return false, tostring(success)
    end

    if success then
        return true
    end

    return false, response or Config.Notifications.NoInventorySpace
end

local function CanReceiveRewards(source, xPlayer, rewards)
    for _, reward in ipairs(rewards or {}) do
        local rewardType = tostring(reward.type or ''):lower()

        if rewardType == 'item' then
            local itemName = reward.name
            local count = math.max(1, math.floor(ToNumber(reward.count or reward.amount, 1)))

            if not itemName or itemName == '' then
                return false, 'Invalid item reward in config.'
            end

            local oxCanCarry, oxError = OxCanCarry(source, itemName, count, reward.metadata)
            if oxCanCarry == false then
                return false, oxError or Config.Notifications.NoInventorySpace
            elseif oxCanCarry == nil then
                if not AllowInventoryFallback() then
                    return false, 'ox_inventory is not started.'
                end

                if xPlayer.canCarryItem and not xPlayer.canCarryItem(itemName, count) then
                    return false, Config.Notifications.NoInventorySpace
                end
            end
        elseif rewardType == 'weapon' then
            local weaponName = reward.name
            if not weaponName or weaponName == '' then
                return false, 'Invalid weapon reward in config.'
            end

            if UsesOxInventory() and (not Config.Inventory or Config.Inventory.WeaponAsItem ~= false) then
                if Config.Rewards and Config.Rewards.PreventDuplicateWeapons and OxItemCount(source, weaponName) > 0 then
                    return false, ('You already have %s.'):format(FormatRewardLabel(reward))
                end

                local oxCanCarry, oxError = OxCanCarry(source, weaponName, 1, BuildWeaponMetadata(reward))
                if oxCanCarry == false then
                    return false, oxError or Config.Notifications.NoInventorySpace
                end
            else
                if not AllowInventoryFallback() then
                    return false, 'ox_inventory is not started.'
                end

                if Config.Rewards and Config.Rewards.PreventDuplicateWeapons and xPlayer.hasWeapon and xPlayer.hasWeapon(weaponName) then
                    return false, ('You already have %s.'):format(FormatRewardLabel(reward))
                end
            end
        elseif rewardType == 'vehicle' and not (Config.VehicleRewards and Config.VehicleRewards.Enabled) then
            return false, 'Vehicle rewards are disabled in config.lua.'
        end
    end

    return true
end

local function ReplacePlaceholders(text, context)
    return tostring(text or ''):gsub('{([%w_]+)}', function(key)
        local value = context[key]
        if value == nil then
            return ''
        end
        return tostring(value)
    end)
end

local function RandomPlate(prefix)
    local cleanPrefix = tostring(prefix or ''):upper():gsub('[^A-Z0-9]', ''):sub(1, 4)
    local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local length = math.max(1, 8 - #cleanPrefix)
    local plate = cleanPrefix

    for _ = 1, length do
        local index = math.random(1, #alphabet)
        plate = plate .. alphabet:sub(index, index)
    end

    return plate:sub(1, 8)
end

local function PlateExists(plate)
    if not Config.VehicleRewards or not Config.VehicleRewards.CheckPlateSQL then
        return false
    end

    local rows = DBFetch(Config.VehicleRewards.CheckPlateSQL, {
        ['@plate'] = plate
    })

    return rows and rows[1] ~= nil
end

local function GenerateUniquePlate(prefix)
    for _ = 1, 25 do
        local plate = RandomPlate(prefix)
        if not PlateExists(plate) then
            return plate
        end
    end

    return RandomPlate(prefix)
end

local function GrantVehicleReward(xPlayer, reward)
    if not Config.VehicleRewards or not Config.VehicleRewards.Enabled then
        return false, 'Vehicle rewards are disabled in config.lua.'
    end

    local model = reward.model or reward.name
    if not model or model == '' then
        return false, 'Invalid vehicle reward in config.'
    end

    local plate = GenerateUniquePlate(reward.platePrefix or Config.VehicleRewards.PlatePrefix)
    local vehicleProperties = {
        model = model,
        plate = plate
    }

    if type(GetHashKey) == 'function' then
        vehicleProperties.model = GetHashKey(model)
    end

    if type(reward.props) == 'table' then
        for key, value in pairs(reward.props) do
            vehicleProperties[key] = value
        end
    end

    local ok, errorMessage = pcall(function()
        DBExecute(Config.VehicleRewards.InsertSQL, {
            ['@owner'] = xPlayer.identifier,
            ['@plate'] = plate,
            ['@vehicle'] = json.encode(vehicleProperties),
            ['@type'] = reward.vehicleType or Config.VehicleRewards.Type or 'car',
            ['@stored'] = reward.stored or Config.VehicleRewards.Stored or 1
        })
    end)

    if not ok then
        return false, errorMessage
    end

    return true, plate
end

local function GrantReward(source, xPlayer, reward, mission)
    local rewardType = tostring(reward.type or ''):lower()
    local amount = math.floor(ToNumber(reward.amount or reward.count, 0))

    if rewardType == 'money' or rewardType == 'cash' then
        if amount <= 0 then
            return false, 'Invalid money reward amount.'
        end
        xPlayer.addMoney(amount)
        return true
    elseif rewardType == 'bank' then
        if amount <= 0 then
            return false, 'Invalid bank reward amount.'
        end
        xPlayer.addAccountMoney('bank', amount)
        return true
    elseif rewardType == 'black_money' then
        if amount <= 0 then
            return false, 'Invalid black money reward amount.'
        end
        xPlayer.addAccountMoney('black_money', amount)
        return true
    elseif rewardType == 'account' then
        if amount <= 0 then
            return false, 'Invalid account reward amount.'
        end
        xPlayer.addAccountMoney(reward.account or 'bank', amount)
        return true
    elseif rewardType == 'item' then
        local itemName = reward.name
        local count = math.max(1, math.floor(ToNumber(reward.count or reward.amount, 1)))

        local oxAdded, oxError = OxAddItem(source, itemName, count, reward.metadata)
        if oxAdded == true then
            return true
        elseif oxAdded == false then
            return false, oxError or Config.Notifications.NoInventorySpace
        end

        if not AllowInventoryFallback() then
            return false, 'ox_inventory is not started.'
        end

        if not xPlayer.addInventoryItem then
            return false, 'Your ESX inventory does not support addInventoryItem.'
        end
        xPlayer.addInventoryItem(itemName, count)
        return true
    elseif rewardType == 'weapon' then
        local weaponName = reward.name
        local ammo = math.max(0, math.floor(ToNumber(reward.ammo, 0)))

        if UsesOxInventory() and (not Config.Inventory or Config.Inventory.WeaponAsItem ~= false) then
            local oxAdded, oxError = OxAddItem(source, weaponName, 1, BuildWeaponMetadata(reward))
            if oxAdded == true then
                return true
            end
            return false, oxError or Config.Notifications.NoInventorySpace
        end

        if not AllowInventoryFallback() then
            return false, 'ox_inventory is not started.'
        end

        if not xPlayer.addWeapon then
            return false, 'Your ESX version does not support addWeapon.'
        end
        xPlayer.addWeapon(weaponName, ammo)
        return true
    elseif rewardType == 'command' then
        if not reward.command or reward.command == '' then
            return false, 'Invalid command reward in config.'
        end

        ExecuteCommand(ReplacePlaceholders(reward.command, {
            source = source,
            identifier = xPlayer.identifier,
            playerName = GetPlayerName(source) or '',
            missionKey = mission.key,
            dayKey = mission.dayKey,
            amount = amount,
            name = reward.name or ''
        }))
        return true
    elseif rewardType == 'vehicle' then
        local ok, plateOrError = GrantVehicleReward(xPlayer, reward)
        if not ok then
            return false, plateOrError
        end
        return true
    end

    return false, ('Unknown reward type: %s'):format(rewardType)
end

local function GrantRewards(source, xPlayer, rewards, mission)
    for _, reward in ipairs(rewards or {}) do
        local ok, errorMessage = GrantReward(source, xPlayer, reward, mission)
        if not ok then
            return false, errorMessage
        end
    end

    return true
end

local function FetchMissionRow(identifier, dayKey, missionKey)
    local rows = DBFetch(([[
        SELECT * FROM %s
        WHERE identifier = @identifier AND day_key = @day_key AND mission_key = @mission_key
        LIMIT 1
    ]]):format(TABLE_NAME), {
        ['@identifier'] = identifier,
        ['@day_key'] = dayKey,
        ['@mission_key'] = missionKey
    })

    return rows and rows[1] or nil
end

local function ClaimMission(source, payload)
    local xPlayer = ESX.GetPlayerFromId(source)
    local state = EnsurePlayerLoaded(source)

    if not xPlayer or not state then
        return {
            ok = false,
            error = Config.Notifications.NotReady
        }
    end

    local missionKey = payload and payload.missionKey
    local dayKey = payload and payload.dayKey or state.dayKey

    if not missionKey or missionKey == '' then
        return {
            ok = false,
            error = Config.Notifications.InvalidMission
        }
    end

    local lockKey = ('%s:%s:%s'):format(state.identifier, dayKey, missionKey)
    if ClaimLocks[lockKey] then
        return {
            ok = false,
            error = Config.Notifications.ClaimBusy
        }
    end

    ClaimLocks[lockKey] = true
    SavePlayer(source, true)

    local row = FetchMissionRow(state.identifier, dayKey, missionKey)
    if not row then
        ClaimLocks[lockKey] = nil
        return {
            ok = false,
            error = Config.Notifications.InvalidMission
        }
    end

    local mission = RowToMission(row, dayKey)

    if mission.claimed then
        ClaimLocks[lockKey] = nil
        return {
            ok = false,
            error = Config.Notifications.AlreadyClaimed,
            state = BuildPublicState(source)
        }
    end

    if not mission.completed then
        ClaimLocks[lockKey] = nil
        return {
            ok = false,
            error = Config.Notifications.NotCompleted,
            state = BuildPublicState(source)
        }
    end

    local canReceive, receiveError = CanReceiveRewards(source, xPlayer, mission.rewards)
    if not canReceive then
        ClaimLocks[lockKey] = nil
        return {
            ok = false,
            error = receiveError,
            state = BuildPublicState(source)
        }
    end

    local granted, grantError = GrantRewards(source, xPlayer, mission.rewards, mission)
    if not granted then
        ClaimLocks[lockKey] = nil
        return {
            ok = false,
            error = grantError,
            state = BuildPublicState(source)
        }
    end

    DBExecute(([[
        UPDATE %s
        SET claimed = 1, claimed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE identifier = @identifier AND day_key = @day_key AND mission_key = @mission_key AND claimed = 0
    ]]):format(TABLE_NAME), {
        ['@identifier'] = state.identifier,
        ['@day_key'] = dayKey,
        ['@mission_key'] = missionKey
    })

    ClaimLocks[lockKey] = nil
    LoadPlayer(source, xPlayer)

    local message = (Config.Notifications.Claimed):format(mission.label)

    return {
        ok = true,
        message = message,
        state = BuildPublicState(source)
    }
end

local function RegisterCallbacks()
    if CallbacksRegistered or not ESX then
        return
    end

    CallbacksRegistered = true

    ESX.RegisterServerCallback(RESOURCE .. ':getState', function(source, callback)
        EnsurePlayerLoaded(source)
        callback(BuildPublicState(source))
    end)

    ESX.RegisterServerCallback(RESOURCE .. ':claim', function(source, callback, payload)
        callback(ClaimMission(source, payload or {}))
    end)
end

local function UpdatePlayerProgress(source, state)
    if not GetPlayerName(source) then
        SavePlayer(source, true)
        PlayerStates[source] = nil
        return
    end

    local currentDayKey = GetDayKey()
    if state.dayKey ~= currentDayKey then
        SavePlayer(source, true)
        LoadPlayer(source)
        TriggerClientEvent(RESOURCE .. ':stateUpdated', source, BuildPublicState(source))
        return
    end

    local now = os.time()
    local delta = now - ToNumber(state.lastProgressAt, now)
    state.lastProgressAt = now

    if delta <= 0 or not IsProgressAllowed(state) then
        return
    end

    delta = math.min(delta, ToNumber(Config.Progress and Config.Progress.MaxTickDeltaSeconds, 120))

    local countingMap = GetCountingMap(state)
    local completedAny = false

    for key, mission in pairs(state.missions or {}) do
        if countingMap[key] and not mission.completed and not mission.claimed then
            local requiredSeconds = math.max(0, math.floor(ToNumber(mission.requiredSeconds, 0)))
            mission.progress = math.min(requiredSeconds, ToNumber(mission.progress, 0) + delta)
            mission.dirty = true

            if requiredSeconds <= 0 or mission.progress >= requiredSeconds then
                mission.progress = requiredSeconds
                mission.completed = true
                completedAny = true

                local template = Config.Notifications and Config.Notifications.MissionCompleted or 'Mission completed: %s'
                Notify(source, template:format(mission.label), 'success')
            end
        end
    end

    if completedAny or now >= ToNumber(state.nextSaveAt, 0) then
        SavePlayer(source, true)
        state.nextSaveAt = now + ToNumber(Config.Progress and Config.Progress.SaveIntervalSeconds, 120)
    end

    if completedAny then
        TriggerClientEvent(RESOURCE .. ':stateUpdated', source, BuildPublicState(source))
    end
end

RegisterNetEvent(RESOURCE .. ':heartbeat', function(payload)
    local source = source
    local state = PlayerStates[source]

    if not state then
        return
    end

    state.lastHeartbeatAt = os.time()
    state.clientActive = not (type(payload) == 'table' and payload.active == false)
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local source = tonumber(playerId) or source
    LoadPlayer(source, xPlayer)
end)

AddEventHandler('playerDropped', function()
    local source = source
    SavePlayer(source, true)
    PlayerStates[source] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then
        return
    end

    for source in pairs(PlayerStates) do
        SavePlayer(source, true)
    end
end)

CreateThread(function()
    math.randomseed(os.time())

    while not TryGetESX() do
        print(('[%s] Waiting for ESX...'):format(RESOURCE))
        Wait(1000)
    end

    for _ = 1, 120 do
        DatabaseDriver = DetectDatabaseDriver()

        if DatabaseDriver and IsDriverReady(DatabaseDriver) then
            break
        end

        Wait(500)
    end

    if not DatabaseDriver or not IsDriverReady(DatabaseDriver) then
        print(('[%s] ERROR: No supported MySQL resource found. Start oxmysql, mysql-async, or ghmattimysql before this resource.'):format(RESOURCE))
        return
    end

    if Config.Database and Config.Database.AutoCreate then
        CreateDatabaseTable()
    end

    DatabaseReady = true
    RegisterCallbacks()

    for _, playerId in ipairs(ESX.GetPlayers()) do
        LoadPlayer(tonumber(playerId) or playerId)
    end

    print(('[%s] Started with %s. Daily missions loaded: %s'):format(RESOURCE, DatabaseDriver, #(Config.Missions or {})))
end)

CreateThread(function()
    while true do
        Wait(math.max(5, ToNumber(Config.Progress and Config.Progress.TickSeconds, 60)) * 1000)

        if DatabaseReady then
            for source, state in pairs(PlayerStates) do
                UpdatePlayerProgress(source, state)
            end
        end
    end
end)
