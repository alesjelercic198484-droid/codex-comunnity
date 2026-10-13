--[[
    shared/bridge.lua - QBCore / ESX / ox_inventory abstraction.

    Everything the rest of the resource needs from the framework goes through
    this file, so switching servers never means editing twenty files.
]]

Bridge = {}

local RESOURCE = 'codex_policecreator'
local QBCore = nil
local ESX = nil
local mode = nil
local loadedHandlers = {}
local usableHandlers = {}
local ready = false

local function resourceStarted(name)
    if not name then return false end
    local state = GetResourceState(name)
    return state == 'started'
end

local function debugPrint(message)
    if Config and Config.Debug then
        print(('[%s] %s'):format(RESOURCE, message))
    end
end

-- ---------------------------------------------------------------------------
-- FRAMEWORK DETECTION
-- ---------------------------------------------------------------------------
function Bridge.Init()
    if ready then return mode end

    local wanted = (Config and Config.Framework) or 'auto'

    if wanted ~= 'esx' and resourceStarted('qb-core') then
        local ok, core = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and core then
            QBCore = core
            mode = 'qbcore'
        end
    end

    if not mode and wanted ~= 'qbcore' and resourceStarted('es_extended') then
        local ok, core = pcall(function()
            return exports.es_extended:getSharedObject()
        end)
        if ok and core then
            ESX = core
            mode = 'esx'
        end
    end

    mode = mode or 'none'
    ready = true
    debugPrint('framework detected: ' .. mode)
    return mode
end

function Bridge.Mode()
    if not ready then Bridge.Init() end
    return mode
end

function Bridge.OxInventory()
    return resourceStarted('ox_inventory')
end

function Bridge.Core()
    Bridge.Init()
    return QBCore or ESX
end

-- ---------------------------------------------------------------------------
-- PLAYER HELPERS
-- ---------------------------------------------------------------------------
local function qbPlayer(src)
    Bridge.Init()
    if not QBCore then return nil end
    local ok, player = pcall(function()
        return QBCore.Functions.GetPlayer(tonumber(src))
    end)
    return (ok and player) or nil
end

local function esxPlayer(src)
    Bridge.Init()
    if not ESX then return nil end
    local ok, player = pcall(function()
        return ESX.GetPlayerFromId(tonumber(src))
    end)
    return (ok and player) or nil
end

--- Stable identifier: citizenid on QBCore, license on ESX.
function Bridge.GetIdentifier(src)
    local player = qbPlayer(src)
    if player then
        local data = player.PlayerData
        if data and data.citizenid then return tostring(data.citizenid) end
        return nil
    end

    player = esxPlayer(src)
    if player then
        local ok, identifier = pcall(function() return player.getIdentifier() end)
        if ok and identifier then return tostring(identifier) end
        if player.identifier then return tostring(player.identifier) end
    end

    return nil
end

function Bridge.GetCharName(src)
    local player = qbPlayer(src)
    if player then
        local info = player.PlayerData and player.PlayerData.charinfo or {}
        return tostring(info.firstname or 'Unknown'), tostring(info.lastname or '')
    end

    player = esxPlayer(src)
    if player then
        local first, last
        local okFirst, firstValue = pcall(function() return player.get('firstName') end)
        local okLast, lastValue = pcall(function() return player.get('lastName') end)
        if okFirst then first = firstValue end
        if okLast then last = lastValue end

        if (not first or first == '') and player.getName then
            local ok, full = pcall(function() return player.getName() end)
            if ok and full then first, last = full:match('^(%S+)%s*(.*)$') end
        end

        return tostring(first or 'Unknown'), tostring(last or '')
    end

    local name = GetPlayerName(tonumber(src))
    if name then
        local first, last = name:match('^(%S+)%s*(.*)$')
        return tostring(first or name), tostring(last or '')
    end

    return 'Unknown', ''
end

function Bridge.GetFullName(src)
    local first, last = Bridge.GetCharName(src)
    return (first .. ' ' .. (last or '')):match('^%s*(.-)%s*$')
end

function Bridge.GetJob(src)
    local player = qbPlayer(src)
    if player then
        local job = player.PlayerData and player.PlayerData.job
        if job then return job.name, tonumber(job.grade and job.grade.level or 0), job.label end
        return nil
    end

    player = esxPlayer(src)
    if player then
        local ok, job = pcall(function() return player.getJob() end)
        if ok and job then return job.name, tonumber(job.grade or 0), job.label end
        if player.job then return player.job.name, tonumber(player.job.grade or 0) end
    end

    return nil
end

function Bridge.SetJob(src, job, grade)
    local player = qbPlayer(src)
    if player then
        local ok = pcall(function()
            player.Functions.SetJob(job, tonumber(grade) or 0)
        end)
        return ok
    end

    player = esxPlayer(src)
    if player then
        local ok = pcall(function()
            player.setJob(job, tonumber(grade) or 0)
        end)
        return ok
    end

    return false
end

--- vector3 of the player ped. Returns nil when the player is unknown.
function Bridge.GetCoords(src)
    local ped = GetPlayerPed(tonumber(src))
    if type(ped) ~= 'number' or ped <= 0 then return nil end
    local coords = GetEntityCoords(ped)
    if not coords then return nil end
    return coords
end

function Bridge.GetPlayers()
    local list = {}
    local ids = GetPlayers()
    for _, id in ipairs(ids or {}) do list[#list + 1] = tonumber(id) end
    return list
end

function Bridge.PlayerExists(src)
    local id = tonumber(src)
    if not id then return false end
    if Bridge.Mode() == 'qbcore' then return qbPlayer(id) ~= nil end
    if Bridge.Mode() == 'esx' then return esxPlayer(id) ~= nil end
    return GetPlayerPed(id) ~= nil and GetPlayerPed(id) ~= 0
end

-- ---------------------------------------------------------------------------
-- MONEY
-- ---------------------------------------------------------------------------
local function accountName()
    return (Config and Config.MoneyAccount) or 'bank'
end

function Bridge.GetMoney(src, account)
    account = account or accountName()

    local player = qbPlayer(src)
    if player then
        local money = player.PlayerData and player.PlayerData.money
        if money and money[account] then return tonumber(money[account]) or 0 end
        return 0
    end

    player = esxPlayer(src)
    if player then
        local ok, value = pcall(function() return player.getAccount(account) end)
        if ok and value then return tonumber(value.money) or 0 end
    end

    return 0
end

function Bridge.AddMoney(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local player = qbPlayer(src)
    if player then
        local ok = pcall(function()
            player.Functions.AddMoney(accountName(), amount, reason or 'department-payout')
        end)
        return ok
    end

    player = esxPlayer(src)
    if player then
        local ok = pcall(function()
            player.addAccountMoney(accountName(), amount)
        end)
        return ok
    end

    return false
end

function Bridge.RemoveMoney(src, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    if Bridge.GetMoney(src) < amount then return false end

    local player = qbPlayer(src)
    if player then
        local ok = pcall(function()
            player.Functions.RemoveMoney(accountName(), amount, reason or 'department-payment')
        end)
        return ok
    end

    player = esxPlayer(src)
    if player then
        local ok = pcall(function()
            player.removeAccountMoney(accountName(), amount)
        end)
        return ok
    end

    return false
end

-- ---------------------------------------------------------------------------
-- INVENTORY
-- ---------------------------------------------------------------------------
function Bridge.HasItem(src, item, amount)
    amount = tonumber(amount) or 1
    src = tonumber(src)

    if Bridge.OxInventory() then
        local ok, count = pcall(function()
            return exports.ox_inventory:Search(src, 'count', item)
        end)
        if ok then
            count = tonumber(count) or 0
            return count >= amount, count
        end
    end

    local player = qbPlayer(src)
    if player then
        local ok, entry = pcall(function()
            return player.Functions.GetItemByName(item)
        end)
        local count = (ok and entry and tonumber(entry.amount)) or 0
        return count >= amount, count
    end

    player = esxPlayer(src)
    if player then
        local count = 0
        local ok, entry = pcall(function() return player.getInventoryItem(item) end)
        if ok and entry then count = tonumber(entry.count) or 0 end
        return count >= amount, count
    end

    return false, 0
end

function Bridge.AddItem(src, item, amount, metadata)
    amount = tonumber(amount) or 1
    src = tonumber(src)
    if amount <= 0 then return false end

    if Bridge.OxInventory() then
        local ok, result = pcall(function()
            return exports.ox_inventory:AddItem(src, item, amount, metadata)
        end)
        return ok and result ~= false
    end

    local player = qbPlayer(src)
    if player then
        local ok, result = pcall(function()
            return player.Functions.AddItem(item, amount, false, metadata)
        end)
        if ok and result then
            pcall(function()
                TriggerClientEvent('inventory:client:ItemBox', src,
                    QBCore.Shared.Items[item] or { name = item, label = item }, 'add', amount)
            end)
        end
        return ok and result ~= false
    end

    player = esxPlayer(src)
    if player then
        local ok = pcall(function()
            player.addInventoryItem(item, amount)
        end)
        return ok
    end

    return false
end

function Bridge.RemoveItem(src, item, amount)
    amount = tonumber(amount) or 1
    src = tonumber(src)

    if Bridge.OxInventory() then
        local ok, result = pcall(function()
            return exports.ox_inventory:RemoveItem(src, item, amount)
        end)
        return ok and result ~= false
    end

    local player = qbPlayer(src)
    if player then
        local ok, result = pcall(function()
            return player.Functions.RemoveItem(item, amount)
        end)
        if ok and result then
            pcall(function()
                TriggerClientEvent('inventory:client:ItemBox', src,
                    QBCore.Shared.Items[item] or { name = item, label = item }, 'remove', amount)
            end)
        end
        return ok and result ~= false
    end

    player = esxPlayer(src)
    if player then
        local ok = pcall(function()
            player.removeInventoryItem(item, amount)
        end)
        return ok
    end

    return false
end

--- Useable item hook (QBCore/ox_inventory) so trackers & bags work out of the box.
function Bridge.RegisterUsableItem(item, handler)
    if not item or item == '' then return end
    usableHandlers[item] = handler

    if Bridge.OxInventory() then
        pcall(function()
            exports.ox_inventory:registerHook(nil, nil)
        end)
    end

    local qb = Bridge.Core()
    if mode == 'qbcore' and qb then
        pcall(function()
            qb.Functions.CreateUseableItem(item, function(source, data)
                local fn = usableHandlers[item]
                if fn then fn(source, data) end
            end)
        end)
    elseif mode == 'esx' and qb then
        pcall(function()
            ESX.RegisterUsableItem(item, function(source)
                local fn = usableHandlers[item]
                if fn then fn(source) end
            end)
        end)
    end
end

function Bridge.UsableHandlers()
    return usableHandlers
end

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------------------
function Bridge.Notify(src, message, kind, length)
    src = tonumber(src)
    if not src or not message then return end

    local player = qbPlayer(src)
    if player then
        pcall(function()
            player.Functions.Notify(tostring(message), kind or 'primary', tonumber(length) or 5000)
        end)
        return
    end

    player = esxPlayer(src)
    if player then
        pcall(function()
            ESX.ShowNotification(tostring(message))
        end)
        return
    end

    TriggerClientEvent(RESOURCE .. ':client:notify', src, tostring(message), kind or 'primary')
end

-- ---------------------------------------------------------------------------
-- PERMISSIONS (ACE / job fallback)
-- ---------------------------------------------------------------------------
function Bridge.IsAdmin(src)
    src = tonumber(src)
    local ace = Config and Config.Ace and Config.Ace.Admin
    if ace and ace ~= false then
        if IsPlayerAceAllowed(src, ace) then return true end
    end

    local job = Bridge.GetJob(src)
    if job and Config and Config.CreatorJobs then
        return Core.TableContains(Config.CreatorJobs, job)
    end

    return false
end

function Bridge.CanCreate(src)
    src = tonumber(src)
    local ace = Config and Config.Ace and Config.Ace.Creator
    if ace and ace ~= false then
        if IsPlayerAceAllowed(src, ace) then return true end
    end

    local job = Bridge.GetJob(src)
    if job and Config and Config.CreatorJobs then
        return Core.TableContains(Config.CreatorJobs, job)
    end

    return false
end

-- ---------------------------------------------------------------------------
-- LIFECYCLE
-- ---------------------------------------------------------------------------
function Bridge.OnPlayerLoaded(handler)
    loadedHandlers[#loadedHandlers + 1] = handler
end

function Bridge.NotifyPlayerLoaded(src)
    for _, handler in ipairs(loadedHandlers) do
        local ok, err = pcall(handler, src)
        if not ok then
            print(('[%s] playerLoaded handler error: %s'):format(RESOURCE, err))
        end
    end
end

if IsDuplicityVersion and IsDuplicityVersion() then
    -- Server side wiring for the two frameworks.
    if resourceStarted('qb-core') then
        AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
            local src = player and player.PlayerData and player.PlayerData.source
            if src then Bridge.NotifyPlayerLoaded(src) end
        end)
    end

    if resourceStarted('es_extended') then
        AddEventHandler('esx:playerLoaded', function(src)
            Bridge.NotifyPlayerLoaded(src)
        end)
    end

    AddEventHandler('playerJoining', function()
        Bridge.NotifyPlayerLoaded(source)
    end)
end
