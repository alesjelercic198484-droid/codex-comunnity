--[[
    codex_bodyharvest - server
    ---------------------------------------------------------------------
    Authority for everything: who may cut, what is still left on a body,
    who gets paid and who receives the police alert / open fire zone.

    Nothing the client sends is trusted. Every request is validated twice,
    once when the cut starts and once when it is finished.
]]

local ESX

if Config.ESX.UseExport and GetResourceState(Config.ESX.ExportName) == 'started' then
    pcall(function() ESX = exports[Config.ESX.ExportName]:getSharedObject() end)
end

if not ESX then
    TriggerEvent(Config.ESX.SharedObjectEvent, function(object) ESX = object end)
end

if not ESX then
    error('[codex_bodyharvest] ESX could not be loaded. Start es_extended before this resource.')
end

local RESOURCE = GetCurrentResourceName()

local partsById = {}
for _, part in ipairs(Config.Parts) do
    partsById[part.id] = part
end

local harvests = {}      -- [targetId] = { deathId = n, taken = {}, busy = {} }
local pending = {}       -- [token]    = { src, target, partId, startedAt, expires }
local pendingBySrc = {}  -- [src]      = token
local cooldowns = {}     -- [src]      = game timer in ms
local alertCooldown = {} -- [src]      = game timer in ms
local sellCooldown = {}  -- [src]      = game timer in ms
local tokenCounter = 0

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------
local function debug(...)
    if Config.Debug then
        print(('[%s]'):format(RESOURCE), ...)
    end
end

local function log(message)
    if Config.Logs.Console then
        print(('[%s] %s'):format(RESOURCE, message))
    end

    if Config.Logs.Webhook and Config.Logs.Webhook ~= '' then
        PerformHttpRequest(Config.Logs.Webhook, function() end, 'POST', json.encode({
            username = Config.Logs.WebhookName,
            content = message
        }), { ['Content-Type'] = 'application/json' })
    end
end

local function notify(src, description, kind, title)
    TriggerClientEvent('codex_bodyharvest:notify', src, description, kind or 'inform', title)
end

local function deny(src, message)
    TriggerClientEvent('codex_bodyharvest:denied', src, message)
end

local formatMoney = Config.FormatMoney

local function isOnline(playerId)
    return playerId and playerId > 0 and GetPlayerName(playerId) ~= nil
end

local function getCoords(playerId)
    local ped = GetPlayerPed(playerId)

    if not ped or ped == 0 then
        return nil
    end

    return GetEntityCoords(ped)
end

local function getState(playerId)
    local ok, state = pcall(function()
        return Player(playerId).state
    end)

    if ok then
        return state
    end

    return nil
end

local function setState(playerId, key, value)
    if not isOnline(playerId) then
        return
    end

    pcall(function()
        Player(playerId).state:set(key, value, true)
    end)
end

local function getDeathId(playerId)
    local state = getState(playerId)
    return (state and state[Config.StateKeys.Death]) or 0
end

--- A player is only "dead" when the ped health confirms it. The replicated
--- state bag alone is never enough, otherwise a modded client could mark
--- himself as dead and let a friend farm body parts.
local function isPlayerDead(playerId)
    local ped = GetPlayerPed(playerId)

    if not ped or ped == 0 then
        return false
    end

    local health = GetEntityHealth(ped) or 0
    local state = getState(playerId)
    local stateDead = state and state[Config.StateKeys.Dead] == true

    if Config.Harvest.ServerHealthCheck and health > Config.Harvest.DeadHealthThreshold then
        return false
    end

    if health <= Config.Harvest.DeadHealthThreshold then
        return true
    end

    return stateDead == true
end

local function hasKnife(src)
    if not Config.Harvest.RequireKnife then
        return true
    end

    local ok, result = pcall(function()
        return exports.ox_inventory:Search(src, 'count', Config.Knives)
    end)

    if not ok or not result then
        return false
    end

    if type(result) == 'number' then
        return result > 0
    end

    for _, amount in pairs(result) do
        if type(amount) == 'number' and amount > 0 then
            return true
        end
    end

    return false
end

local function countItem(src, item)
    local ok, result = pcall(function()
        return exports.ox_inventory:Search(src, 'count', item)
    end)

    if not ok or type(result) ~= 'number' then
        return 0
    end

    return result
end

--- An unknown / not yet streamed entity reports 0,0,0 on the server. Treating
--- that as a valid position would let a cheater "reach" anybody, so it is
--- refused explicitly.
local function isUnknownPosition(coords)
    return coords.x == 0.0 and coords.y == 0.0 and coords.z == 0.0
end

local function withinDistance(srcId, targetId, maxDistance)
    local a = getCoords(srcId)
    local b = getCoords(targetId)

    if not a or not b or isUnknownPosition(a) or isUnknownPosition(b) then
        return false
    end

    return #(a - b) <= maxDistance
end

-- ---------------------------------------------------------------------------
-- HARVEST RECORDS (one finger, one ear, one tongue per dead body)
-- ---------------------------------------------------------------------------
local function publishParts(targetId, record)
    if not record then
        setState(targetId, Config.StateKeys.Parts, nil)
        return
    end

    local parts = {}

    for partId, taken in pairs(record.taken) do
        if taken then
            parts[partId] = true
        end
    end

    setState(targetId, Config.StateKeys.Parts, next(parts) and parts or nil)
end

local function clearRecord(targetId)
    if harvests[targetId] then
        harvests[targetId] = nil
        debug('record cleared for', targetId)
    end

    publishParts(targetId, nil)
end

local function getRecord(targetId)
    local deathId = getDeathId(targetId)
    local record = harvests[targetId]

    if record and record.deathId ~= deathId then
        -- The player died again: the old body is gone, everything resets.
        record = nil
        harvests[targetId] = nil
        publishParts(targetId, nil)
    end

    if not record then
        record = { deathId = deathId, taken = {}, busy = {} }
        harvests[targetId] = record
    end

    return record
end

AddStateBagChangeHandler(Config.StateKeys.Dead, nil, function(bagName, _, value)
    local playerId = tonumber(tostring(bagName):match('player:(%d+)'))

    if not playerId then
        return
    end

    if value ~= true and Config.Harvest.ResetOnRespawn then
        clearRecord(playerId)
    end
end)

AddStateBagChangeHandler(Config.StateKeys.Death, nil, function(bagName, _, value)
    local playerId = tonumber(tostring(bagName):match('player:(%d+)'))

    if not playerId then
        return
    end

    local record = harvests[playerId]

    if record and record.deathId ~= value then
        clearRecord(playerId)
    end
end)

-- ---------------------------------------------------------------------------
-- POLICE ALERT + OPEN FIRE ZONE
-- ---------------------------------------------------------------------------
local function getOnlinePlayers()
    local players = {}

    for _, id in ipairs(GetPlayers()) do
        players[#players + 1] = tonumber(id)
    end

    return players
end

local function getPlayersWithJobs(jobs)
    local wanted = {}

    for _, job in ipairs(jobs) do
        wanted[job] = true
    end

    local result = {}

    if ESX.GetExtendedPlayers then
        for job in pairs(wanted) do
            local ok, list = pcall(ESX.GetExtendedPlayers, 'job', job)

            if ok and list then
                for _, xPlayer in pairs(list) do
                    if xPlayer and xPlayer.source then
                        result[xPlayer.source] = true
                    end
                end
            end
        end

        return result
    end

    for _, playerId in ipairs(getOnlinePlayers()) do
        local xPlayer = ESX.GetPlayerFromId(playerId)

        if xPlayer and xPlayer.job and wanted[xPlayer.job.name] then
            result[playerId] = true
        end
    end

    return result
end

local function jitterCoords(coords)
    local jitter = tonumber(Config.Alert.Jitter) or 0.0

    if jitter <= 0.0 then
        return { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 }
    end

    -- math.random(min, max) needs integers in Lua 5.4, so the offset is built
    -- from the float generator instead.
    local function offset()
        return ((math.random() * 2.0) - 1.0) * jitter
    end

    return {
        x = coords.x + offset(),
        y = coords.y + offset(),
        z = coords.z + 0.0
    }
end

local function dispatchAlert(harvesterId, coords)
    if not Config.Alert.Enabled or not coords then
        return
    end

    local now = GetGameTimer()

    if Config.Alert.Cooldown > 0 and alertCooldown[harvesterId] and now < alertCooldown[harvesterId] then
        debug('alert skipped (cooldown) for', harvesterId)
        return
    end

    alertCooldown[harvesterId] = now + (Config.Alert.Cooldown * 1000)

    local reported = jitterCoords(coords)
    local officers = getPlayersWithJobs(Config.Alert.Jobs)
    local officerCount = 0

    for officerId in pairs(officers) do
        officerCount = officerCount + 1

        TriggerClientEvent('codex_bodyharvest:policeAlert', officerId, {
            coords = reported,
            duration = Config.Alert.Blip.Duration,
            title = Config.Text.PoliceAlertTitle,
            body = Config.Text.PoliceAlertBody
        })
    end

    log(('police alert "%s" sent to %s officer(s) at %.2f %.2f %.2f')
        :format(Config.Text.PoliceAlertTitle, officerCount, reported.x, reported.y, reported.z))

    if not Config.OpenFireZone.Enabled then
        return
    end

    SetTimeout(Config.OpenFireZone.Delay * 1000, function()
        local police = Config.OpenFireZone.ExcludePolice and getPlayersWithJobs(Config.Alert.Jobs) or {}

        for _, playerId in ipairs(getOnlinePlayers()) do
            local shouldNotify = true

            if Config.OpenFireZone.ExcludeHarvester and playerId == harvesterId then
                shouldNotify = false
            end

            if police[playerId] then
                shouldNotify = false
            end

            TriggerClientEvent('codex_bodyharvest:openFireZone', playerId, {
                coords = reported,
                radius = Config.OpenFireZone.Radius,
                duration = Config.OpenFireZone.Duration,
                title = Config.Text.ZoneTitle,
                body = Config.Text.ZoneBody,
                notify = shouldNotify
            })
        end

        log(('open fire zone broadcast at %.2f %.2f %.2f (radius %s, %ss)')
            :format(reported.x, reported.y, reported.z, Config.OpenFireZone.Radius, Config.OpenFireZone.Duration))
    end)
end

-- ---------------------------------------------------------------------------
-- HARVEST REQUEST
-- ---------------------------------------------------------------------------
local function releasePending(token, clearBusy)
    local entry = pending[token]

    if not entry then
        return
    end

    pending[token] = nil

    if pendingBySrc[entry.src] == token then
        pendingBySrc[entry.src] = nil
    end

    if clearBusy ~= false then
        local record = harvests[entry.target]

        if record and record.busy[entry.partId] == entry.src then
            record.busy[entry.partId] = nil
        end
    end
end

RegisterNetEvent('codex_bodyharvest:request', function(targetId, partId)
    local src = source
    targetId = tonumber(targetId)

    local part = partsById[partId]

    if not part or not targetId then
        return deny(src, Config.Text.InvalidTarget)
    end

    if pendingBySrc[src] then
        return deny(src, Config.Text.Busy)
    end

    local now = GetGameTimer()

    if cooldowns[src] and now < cooldowns[src] then
        return deny(src, Config.Text.Cooldown)
    end

    if not isOnline(targetId) then
        return deny(src, Config.Text.InvalidTarget)
    end

    if targetId == src and not Config.Harvest.AllowSelf then
        return deny(src, Config.Text.InvalidTarget)
    end

    if Config.Harvest.RequireAlive and isPlayerDead(src) then
        return deny(src, Config.Text.DeadHarvester)
    end

    if not isPlayerDead(targetId) then
        return deny(src, Config.Text.NotDead)
    end

    if not withinDistance(src, targetId, Config.Harvest.ServerDistance) then
        return deny(src, Config.Text.TooFar)
    end

    if not hasKnife(src) then
        return deny(src, Config.Text.NoKnife)
    end

    local record = getRecord(targetId)

    if record.taken[part.id] then
        return deny(src, Config.Text.AlreadyTaken)
    end

    if record.busy[part.id] and isOnline(record.busy[part.id]) then
        return deny(src, Config.Text.InProgress)
    end

    tokenCounter = tokenCounter + 1

    local token = ('%d:%d:%d'):format(src, tokenCounter, math.random(100000, 999999))

    record.busy[part.id] = src

    pending[token] = {
        src = src,
        target = targetId,
        partId = part.id,
        deathId = record.deathId,
        startedAt = now,
        expires = now + (part.duration + (Config.Harvest.PendingTimeout * 1000))
    }

    pendingBySrc[src] = token

    debug(('%s started cutting %s from %s'):format(src, part.id, targetId))

    TriggerClientEvent('codex_bodyharvest:begin', src, token, targetId, part.id)
end)

RegisterNetEvent('codex_bodyharvest:finish', function(token, success)
    local src = source
    local entry = pending[token]

    if not entry or entry.src ~= src then
        return
    end

    local part = partsById[entry.partId]

    if not part then
        releasePending(token)
        return
    end

    if not success then
        releasePending(token)
        return
    end

    local elapsed = GetGameTimer() - entry.startedAt

    if elapsed < (part.duration * Config.Harvest.MinDurationFactor) then
        releasePending(token)
        log(('%s (%s) finished a cut too fast (%sms), request rejected.')
            :format(GetPlayerName(src) or 'unknown', src, elapsed))
        return deny(src, Config.Text.InvalidTarget)
    end

    local targetId = entry.target

    if not isOnline(targetId) then
        releasePending(token)
        return deny(src, Config.Text.InvalidTarget)
    end

    -- Somebody who got shot while cutting does not finish the job.
    if Config.Harvest.RequireAlive and isPlayerDead(src) then
        releasePending(token)
        return deny(src, Config.Text.DeadHarvester)
    end

    if not isPlayerDead(targetId) then
        releasePending(token)
        return deny(src, Config.Text.NotDead)
    end

    if not withinDistance(src, targetId, Config.Harvest.ServerDistance) then
        releasePending(token)
        return deny(src, Config.Text.TooFar)
    end

    if not hasKnife(src) then
        releasePending(token)
        return deny(src, Config.Text.NoKnife)
    end

    local record = getRecord(targetId)

    if record.deathId ~= entry.deathId or record.taken[part.id] then
        releasePending(token)
        return deny(src, Config.Text.AlreadyTaken)
    end

    local canCarry = true
    local ok, result = pcall(function()
        return exports.ox_inventory:CanCarryItem(src, part.item, 1)
    end)

    if ok and result == false then
        canCarry = false
    end

    if not canCarry then
        releasePending(token)
        return deny(src, Config.Text.NoSpace)
    end

    local added = false
    local addOk, addResult = pcall(function()
        return exports.ox_inventory:AddItem(src, part.item, 1)
    end)

    if addOk then
        added = addResult ~= false
    end

    if not added then
        releasePending(token)
        return deny(src, Config.Text.NoSpace)
    end

    record.taken[part.id] = src
    releasePending(token)
    publishParts(targetId, record)

    cooldowns[src] = GetGameTimer() + (Config.Harvest.Cooldown * 1000)

    notify(src, Config.Text.HarvestSuccess:format(part.noun or part.id), 'success')

    log(('%s (%s) cut a %s from %s (%s)')
        :format(GetPlayerName(src) or 'unknown', src, part.id, GetPlayerName(targetId) or 'unknown', targetId))

    dispatchAlert(src, getCoords(targetId) or getCoords(src))
end)

-- Releases cuts that were never finished (crash, timeout, disconnect).
CreateThread(function()
    while true do
        Wait(5000)

        local now = GetGameTimer()

        for token, entry in pairs(pending) do
            if now > entry.expires or not isOnline(entry.src) then
                debug('pending cut expired', token)
                releasePending(token)
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- SELLING TO THE HIDDEN DEALER
-- ---------------------------------------------------------------------------
RegisterNetEvent('codex_bodyharvest:sell', function(index)
    local src = source

    if not Config.Dealer.Enabled then
        return
    end

    index = tonumber(index)

    local deal = index and Config.Dealer.Deals[index]

    if not deal then
        return deny(src, Config.Text.SellFailed)
    end

    local now = GetGameTimer()

    if sellCooldown[src] and now < sellCooldown[src] then
        return deny(src, Config.Text.SellCooldown)
    end

    -- A refused sale only costs a short anti spam lock, the real cooldown is
    -- started once the deal actually happened.
    sellCooldown[src] = now + 500

    local coords = getCoords(src)
    local dealer = Config.Dealer.Coords

    if not coords or #(coords - vector3(dealer.x, dealer.y, dealer.z)) > Config.Dealer.ServerDistance then
        return deny(src, Config.Text.TooFar)
    end

    local xPlayer = ESX.GetPlayerFromId(src)

    if not xPlayer then
        return
    end

    local available = countItem(src, deal.item)

    if available < deal.min then
        return deny(src, Config.Text.SellNotEnough:format(deal.min, deal.name or deal.item))
    end

    local amount = Config.Dealer.SellAll and available or deal.min

    local removed = false
    local ok, result = pcall(function()
        return exports.ox_inventory:RemoveItem(src, deal.item, amount)
    end)

    if ok then
        removed = result ~= false
    end

    if not removed then
        return deny(src, Config.Text.SellFailed)
    end

    sellCooldown[src] = GetGameTimer() + (Config.Dealer.Cooldown * 1000)

    local total = amount * deal.price

    xPlayer.addAccountMoney(Config.Dealer.Account, total, 'Body part sale')

    notify(src, Config.Text.SellSuccess:format(amount, deal.name or deal.item, formatMoney(total)), 'success')

    log(('%s (%s) sold %sx %s for $%s (%s)')
        :format(GetPlayerName(src) or 'unknown', src, amount, deal.item, formatMoney(total), Config.Dealer.Account))
end)

-- ---------------------------------------------------------------------------
-- CLEAN UP
-- ---------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source

    local token = pendingBySrc[src]

    if token then
        releasePending(token)
    end

    cooldowns[src] = nil
    alertCooldown[src] = nil
    sellCooldown[src] = nil
    harvests[src] = nil

    for activeToken, entry in pairs(pending) do
        if entry.target == src then
            releasePending(activeToken)
        end
    end
end)
