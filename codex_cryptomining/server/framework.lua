--[[
    Framework bridge: ESX, money, inventory, notifications, logs.
    Everything the rest of the server code needs to talk to the outside world
    goes through here, so swapping an inventory is a one line change.
]]

CodexCryptoFW = CodexCryptoFW or {}

local FW = CodexCryptoFW
local Crypto = CodexCrypto
local RESOURCE = GetCurrentResourceName()

FW.ESX = nil

local function IsStarted(resourceName)
    return GetResourceState(resourceName) == 'started'
end

FW.IsStarted = IsStarted

function FW.GetESX()
    if FW.ESX then
        return FW.ESX
    end

    if Config.ESX and Config.ESX.UseExport ~= false then
        local exportName = Config.ESX.ExportName or 'es_extended'
        local ok, object = pcall(function()
            return exports[exportName]:getSharedObject()
        end)

        if ok and object then
            FW.ESX = object
            return FW.ESX
        end
    end

    TriggerEvent((Config.ESX and Config.ESX.SharedObjectEvent) or 'esx:getSharedObject', function(object)
        FW.ESX = object
    end)

    return FW.ESX
end

function FW.GetPlayer(source)
    local ESX = FW.GetESX()
    if not ESX then
        return nil
    end

    local id = tonumber(source)
    if not id or id <= 0 then
        return nil
    end

    return ESX.GetPlayerFromId(id)
end

function FW.GetIdentifier(source)
    local xPlayer = FW.GetPlayer(source)
    return xPlayer and xPlayer.identifier or nil
end

function FW.GetName(source)
    local xPlayer = FW.GetPlayer(source)
    if not xPlayer then
        return GetPlayerName(source) or 'Unknown'
    end
    return xPlayer.getName and xPlayer.getName() or (GetPlayerName(source) or 'Unknown')
end

function FW.GetPlayerByIdentifier(identifier)
    local ESX = FW.GetESX()
    if not ESX or not identifier then
        return nil
    end

    -- Modern ESX exposes GetExtendedPlayers; legacy ESX only has GetPlayers
    -- returning source ids. Support both so the resource survives older cores.
    local players = {}

    if ESX.GetExtendedPlayers then
        local ok, result = pcall(ESX.GetExtendedPlayers)
        if ok and type(result) == 'table' then
            players = result
        end
    elseif ESX.GetPlayers then
        local ok, ids = pcall(ESX.GetPlayers)
        if ok and type(ids) == 'table' then
            for _, playerId in ipairs(ids) do
                local xPlayer = ESX.GetPlayerFromId(playerId)
                if xPlayer then
                    players[#players + 1] = xPlayer
                end
            end
        end
    end

    for _, xPlayer in pairs(players) do
        if xPlayer and xPlayer.identifier == identifier then
            return xPlayer
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- MONEY
-- ---------------------------------------------------------------------------
function FW.GetAccountMoney(xPlayer, account)
    if not xPlayer then
        return 0
    end

    if account == 'money' or account == 'cash' then
        return Crypto.ToInt(xPlayer.getMoney and xPlayer.getMoney() or 0, 0)
    end

    local accountObject = xPlayer.getAccount and xPlayer.getAccount(account)
    if accountObject then
        return Crypto.ToInt(accountObject.money, 0)
    end

    return 0
end

function FW.CanAfford(source, amount, account)
    local xPlayer = FW.GetPlayer(source)
    if not xPlayer then
        return false
    end

    return FW.GetAccountMoney(xPlayer, account or Config.Money.BuyAccount) >= math.floor(Crypto.ToNumber(amount, 0))
end

function FW.RemoveMoney(source, amount, account)
    local xPlayer = FW.GetPlayer(source)
    local value = math.floor(Crypto.ToNumber(amount, 0))

    if not xPlayer or value <= 0 then
        return value <= 0
    end

    account = account or Config.Money.BuyAccount

    if FW.GetAccountMoney(xPlayer, account) < value then
        return false
    end

    if account == 'money' or account == 'cash' then
        xPlayer.removeMoney(value)
    else
        xPlayer.removeAccountMoney(account, value)
    end

    return true
end

function FW.AddMoney(source, amount, account)
    local xPlayer = FW.GetPlayer(source)
    local value = math.floor(Crypto.ToNumber(amount, 0))

    if not xPlayer or value <= 0 then
        return false
    end

    account = account or Config.Money.SellAccount

    if account == 'money' or account == 'cash' then
        xPlayer.addMoney(value)
    else
        xPlayer.addAccountMoney(account, value)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- INVENTORY
-- ---------------------------------------------------------------------------
local inventoryType = nil

function FW.GetInventoryType()
    if inventoryType then
        return inventoryType
    end

    local configured = (Config.Inventory and Config.Inventory.Type) or 'auto'

    if configured ~= 'auto' then
        inventoryType = configured
    elseif IsStarted('ox_inventory') then
        inventoryType = 'ox_inventory'
    else
        inventoryType = 'esx'
    end

    return inventoryType
end

--- Resolves a logical item key (gpu, cpu, ...) to the real item name.
function FW.Item(key)
    local items = (Config.Inventory and Config.Inventory.Items) or {}
    return items[key] or key
end

function FW.GetItemCount(source, key)
    local itemName = FW.Item(key)

    if FW.GetInventoryType() == 'ox_inventory' then
        -- GetItemCount only exists on recent ox_inventory builds; Search has
        -- been available for years. Try the modern export, fall back to Search.
        local ok, count = pcall(function()
            return exports.ox_inventory:GetItemCount(source, itemName)
        end)

        if ok and count ~= nil then
            return Crypto.ToInt(count, 0)
        end

        local searchOk, searchCount = pcall(function()
            return exports.ox_inventory:Search(source, 'count', itemName)
        end)

        if searchOk and searchCount ~= nil then
            return Crypto.ToInt(searchCount, 0)
        end

        return 0
    end

    local xPlayer = FW.GetPlayer(source)
    if not xPlayer then
        return 0
    end

    local item = xPlayer.getInventoryItem and xPlayer.getInventoryItem(itemName)
    return item and Crypto.ToInt(item.count, 0) or 0
end

function FW.CanCarry(source, key, count)
    local itemName = FW.Item(key)
    count = math.max(1, Crypto.ToInt(count, 1))

    if FW.GetInventoryType() == 'ox_inventory' then
        local ok, result = pcall(function()
            return exports.ox_inventory:CanCarryItem(source, itemName, count)
        end)
        if ok then
            return result ~= false
        end
        return true
    end

    local xPlayer = FW.GetPlayer(source)
    if not xPlayer then
        return false
    end

    if xPlayer.canCarryItem then
        local ok, result = pcall(xPlayer.canCarryItem, itemName, count)
        if ok then
            return result ~= false
        end
    end

    return true
end

function FW.AddItem(source, key, count)
    local itemName = FW.Item(key)
    count = math.max(1, Crypto.ToInt(count, 1))

    if FW.GetInventoryType() == 'ox_inventory' then
        -- AddItem returns `success, response`. pcall prepends its own status,
        -- so the real return value is the SECOND result, not the first.
        local ok, success = pcall(function()
            return exports.ox_inventory:AddItem(source, itemName, count)
        end)

        if not ok then
            print(('[%s] ox_inventory:AddItem failed: %s'):format(RESOURCE, tostring(success)))
            return false
        end

        -- Older builds return nothing at all on success.
        return success ~= false
    end

    local xPlayer = FW.GetPlayer(source)
    if not xPlayer then
        return false
    end

    local ok = pcall(xPlayer.addInventoryItem, itemName, count)
    return ok
end

function FW.RemoveItem(source, key, count)
    local itemName = FW.Item(key)
    count = math.max(1, Crypto.ToInt(count, 1))

    if FW.GetItemCount(source, key) < count then
        return false
    end

    if FW.GetInventoryType() == 'ox_inventory' then
        local ok, success = pcall(function()
            return exports.ox_inventory:RemoveItem(source, itemName, count)
        end)

        if not ok then
            print(('[%s] ox_inventory:RemoveItem failed: %s'):format(RESOURCE, tostring(success)))
            return false
        end

        return success ~= false
    end

    local xPlayer = FW.GetPlayer(source)
    if not xPlayer then
        return false
    end

    local ok = pcall(xPlayer.removeInventoryItem, itemName, count)
    return ok
end

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------------
function FW.Notify(source, message, notificationType)
    if not source or not message or message == '' then
        return
    end

    TriggerClientEvent(RESOURCE .. ':notify', source, message, notificationType or 'inform')
end

function FW.NotifyIdentifier(identifier, message, notificationType)
    local xPlayer = FW.GetPlayerByIdentifier(identifier)
    if xPlayer then
        FW.Notify(xPlayer.source, message, notificationType)
    end
end

-- ---------------------------------------------------------------------------
-- DISTANCE (OneSync aware)
-- ---------------------------------------------------------------------------
-- Server side GetEntityCoords only returns real coordinates when OneSync is
-- enabled. On a legacy (non-OneSync) server it returns vector3(0,0,0) for
-- every player, which would make every distance check fail and lock players
-- out of the whole resource. We detect that once and skip distance checks
-- instead of breaking the script, while warning the owner in the console.
local onesyncChecked = false
local onesyncAvailable = true

function FW.IsOneSyncAvailable()
    if onesyncChecked then
        return onesyncAvailable
    end

    local convar = GetConvar('onesync', GetConvar('onesync_enabled', 'off'))
    onesyncAvailable = convar ~= 'off' and convar ~= 'false' and convar ~= ''

    onesyncChecked = true

    if not onesyncAvailable then
        print(('[%s] ^3WARNING: OneSync is disabled. Server side distance checks are skipped, which weakens anti-cheat protection. Enable OneSync for full security.^0'):format(RESOURCE))
    end

    return onesyncAvailable
end

--- Distance between a player and a point. Returns nil when it cannot be
--- measured (no OneSync / no ped), so callers can decide what to do.
function FW.GetDistance(source, target)
    if not target then
        return nil
    end

    if not FW.IsOneSyncAvailable() then
        return nil
    end

    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)

    local dx = coords.x - target.x
    local dy = coords.y - target.y
    local dz = coords.z - (target.z or coords.z)

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- True when the player is within `maxDistance` of ANY of the given points.
--- Unmeasurable distance is treated as "allowed" so the resource stays usable.
function FW.IsNear(source, points, maxDistance)
    if type(points) ~= 'table' then
        return true
    end

    -- A single vector was passed instead of a list.
    if points.x then
        points = { points }
    end

    if #points == 0 then
        return true
    end

    local measured = false

    for _, point in ipairs(points) do
        local distance = FW.GetDistance(source, point)

        if distance ~= nil then
            measured = true

            if distance <= maxDistance then
                return true
            end
        end
    end

    -- Nothing could be measured at all: do not lock the player out.
    return not measured
end

-- ---------------------------------------------------------------------------
-- POLICE / DISPATCH
-- ---------------------------------------------------------------------------
function FW.CountPolice()
    local ESX = FW.GetESX()
    if not ESX then
        return 0
    end

    local jobs = {}
    for _, job in ipairs(Config.Robbery.PoliceJobs or {}) do
        jobs[job] = true
    end

    -- Legacy ESX has no GetExtendedPlayers; fall back to GetPlayers ids.
    local players = {}

    if ESX.GetExtendedPlayers then
        local ok, result = pcall(ESX.GetExtendedPlayers)
        if ok and type(result) == 'table' then
            players = result
        end
    elseif ESX.GetPlayers then
        local ok, ids = pcall(ESX.GetPlayers)
        if ok and type(ids) == 'table' then
            for _, playerId in ipairs(ids) do
                local xPlayer = ESX.GetPlayerFromId(playerId)
                if xPlayer then
                    players[#players + 1] = xPlayer
                end
            end
        end
    end

    local count = 0
    for _, xPlayer in pairs(players) do
        if xPlayer and xPlayer.job and jobs[xPlayer.job.name] then
            count = count + 1
        end
    end

    return count
end

function FW.Dispatch(coords, warehouseLabel)
    if not Config.Dispatch or Config.Dispatch.Enabled == false then
        return
    end

    local payload = {
        coords = coords,
        title = Config.Dispatch.Title,
        message = ('%s (%s)'):format(Config.Dispatch.Message, warehouseLabel or 'unknown'),
        code = Config.Dispatch.Code,
        jobs = Config.Dispatch.Jobs
    }

    local dispatchType = Config.Dispatch.Type or 'none'

    if dispatchType == 'none' then
        return
    end

    local ok, err = pcall(function()
        if dispatchType == 'custom' then
            TriggerEvent(Config.Dispatch.CustomEvent, payload)
        elseif dispatchType == 'cd_dispatch' then
            TriggerClientEvent('cd_dispatch:AddNotification', -1, {
                job_table = Config.Dispatch.Jobs,
                coords = coords,
                title = Config.Dispatch.Code .. ' - ' .. Config.Dispatch.Title,
                message = payload.message,
                flash = 0,
                unique_id = tostring(math.random(10000, 99999)),
                blip = { sprite = 492, scale = 1.0, colour = 1, flashes = false, text = Config.Dispatch.Title, time = 5, radius = 0 }
            })
        elseif dispatchType == 'qs-dispatch' then
            exports['qs-dispatch']:CustomAlert({
                coords = coords,
                job = Config.Dispatch.Jobs,
                message = payload.message,
                blipSprite = 492,
                blipColour = 1,
                blipScale = 1.0,
                blipLength = 3
            })
        elseif dispatchType == 'ps-dispatch' then
            TriggerEvent('ps-dispatch:server:notify', {
                dispatchcodename = 'cryptorobbery',
                dispatchCode = Config.Dispatch.Code,
                firstStreet = payload.message,
                gender = 'Unknown',
                model = nil,
                plate = nil,
                priority = 2,
                origin = { x = coords.x, y = coords.y, z = coords.z },
                dispatchMessage = payload.message,
                job = Config.Dispatch.Jobs
            })
        elseif dispatchType == 'core_dispatch' then
            TriggerEvent('core_dispatch:addCall', Config.Dispatch.Code, Config.Dispatch.Title, { { icon = 'fa-bitcoin', info = payload.message } }, { coords.x, coords.y, coords.z }, Config.Dispatch.Jobs, 15000, 492, 1)
        elseif dispatchType == 'rcore_dispatch' then
            TriggerEvent('rcore_dispatch:server:sendAlert', {
                coords = coords,
                job = Config.Dispatch.Jobs,
                message = payload.message,
                dispatchCode = Config.Dispatch.Code
            })
        else
            TriggerEvent(Config.Dispatch.CustomEvent, payload)
        end
    end)

    if not ok then
        print(('[%s] Dispatch failed (%s): %s'):format(RESOURCE, dispatchType, err))
    end
end

-- ---------------------------------------------------------------------------
-- WEBHOOKS
-- ---------------------------------------------------------------------------
function FW.Log(category, title, description, fields)
    if not Config.Webhooks or Config.Webhooks.Enabled == false then
        return
    end

    local url = Config.Webhooks.Links and Config.Webhooks.Links[category]
    if not url or url == '' then
        return
    end

    local embedFields = {}
    for _, field in ipairs(fields or {}) do
        embedFields[#embedFields + 1] = {
            name = tostring(field.name or '-'),
            value = tostring(field.value or '-'),
            inline = field.inline ~= false
        }
    end

    local payload = {
        username = Config.Webhooks.Name or 'CodeX CryptoMining',
        avatar_url = (Config.Webhooks.Avatar ~= '' and Config.Webhooks.Avatar) or nil,
        embeds = { {
            title = tostring(title or 'Log'),
            description = tostring(description or ''),
            color = Crypto.ToInt(Config.Webhooks.Color, 3066993),
            fields = embedFields,
            footer = { text = os.date('%Y-%m-%d %H:%M:%S') }
        } }
    }

    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end
