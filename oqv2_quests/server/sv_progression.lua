--[[ OQV2 QUESTS — Player progression: XP, levels, unlocks, discovery
     Made with CodeX Dev. ]]

OQ.Progression = {}

--- cache[src] = { identifier, name, xp, level, completed, data, progress = {}, discovered = {}, active = nil }
local cache = {}

-------------------------------------------------------------------------------
-- CACHE
-------------------------------------------------------------------------------
function OQ.Progression.load(src)
    local identifier = OQ.Server.getIdentifier(src)
    if not identifier then return nil end

    local player = OQ.DB.loadPlayer(identifier)
    player.name       = OQ.Server.getName(src)
    player.progress   = OQ.DB.loadProgress(identifier)
    player.discovered = OQ.DB.loadDiscovered(identifier)
    player.active     = nil

    -- resolve stored xp into a level (authoritative)
    local resolved = OQ.resolveXP(player.xp)
    player.level = resolved.level

    cache[src] = player
    OQ.debug('loaded progression for', identifier, 'level', player.level)
    return player
end

function OQ.Progression.get(src, autoload)
    local p = cache[src]
    if not p and autoload ~= false then
        p = OQ.Progression.load(src)
    end
    return p
end

function OQ.Progression.unload(src)
    local p = cache[src]
    if p then
        OQ.DB.savePlayer(p)
        cache[src] = nil
    end
end

function OQ.Progression.all()
    return cache
end

-------------------------------------------------------------------------------
-- XP / LEVELS
-------------------------------------------------------------------------------
function OQ.Progression.addXP(src, amount)
    if not Config.Progression.enabled then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    local p = OQ.Progression.get(src)
    if not p then return end

    local before = OQ.resolveXP(p.xp)
    p.xp = p.xp + amount
    local after = OQ.resolveXP(p.xp)
    p.level = after.level

    OQ.DB.savePlayer(p)

    TriggerClientEvent('oqv2:client:xp', src, {
        gained  = amount,
        level   = after.level,
        xp      = after.xp,
        need    = after.need,
        percent = after.percent,
        total   = after.total,
    })

    if after.level > before.level then
        for lvl = before.level + 1, after.level do
            OQ.Progression.grantLevelReward(src, lvl)
        end
        TriggerClientEvent('oqv2:client:levelUp', src, after.level)
        OQ.DB.log(p.identifier, p.name, 'level_up', { level = after.level })
    end
end

function OQ.Progression.grantLevelReward(src, level)
    local reward = Config.Progression.levelRewards and Config.Progression.levelRewards[level]
    if not reward then return end
    if reward.money and reward.money > 0 then
        OQ.Server.addMoney(src, 'bank', reward.money)
    end
    for _, item in ipairs(reward.items or {}) do
        if OQ.Server.canCarry(src, item.name, item.count) then
            OQ.Server.addItem(src, item.name, item.count)
        end
    end
end

function OQ.Progression.getLevel(src)
    local p = OQ.Progression.get(src)
    return p and p.level or 1
end

function OQ.Progression.setXP(src, total)
    local p = OQ.Progression.get(src)
    if not p then return false end
    p.xp = math.max(0, math.floor(tonumber(total) or 0))
    p.level = OQ.resolveXP(p.xp).level
    OQ.DB.savePlayer(p)
    TriggerClientEvent('oqv2:client:syncPlayer', src, OQ.Progression.buildPayload(src))
    return true
end

-------------------------------------------------------------------------------
-- MISSION PROGRESS ENTRIES
-------------------------------------------------------------------------------
function OQ.Progression.entry(src, missionUid, create)
    local p = OQ.Progression.get(src)
    if not p then return nil end
    local e = p.progress[missionUid]
    if not e and create then
        e = { status = 'available', progress = {}, completions = 0, lastCompleted = 0, windowStart = 0, windowCount = 0 }
        p.progress[missionUid] = e
    end
    return e
end

function OQ.Progression.saveEntry(src, missionUid)
    local p = OQ.Progression.get(src)
    if not p then return end
    local e = p.progress[missionUid]
    if not e then return end
    OQ.DB.saveProgress(p.identifier, missionUid, e)
end

function OQ.Progression.isCompleted(src, missionUid)
    local e = OQ.Progression.entry(src, missionUid, false)
    return e ~= nil and (e.completions or 0) > 0
end

--- Remaining cooldown in seconds (0 = ready).
function OQ.Progression.cooldownLeft(src, mission)
    local cd = mission.cooldown or {}
    local e  = OQ.Progression.entry(src, mission.uid, false)
    if not e then return 0 end

    if cd.type == 'infinite' then return 0 end

    if cd.type == 'none' then
        return (e.completions or 0) > 0 and -1 or 0    -- -1 = permanently done
    end

    local seconds = cd.seconds or 0
    if seconds <= 0 then return 0 end

    -- Rolling window: `maxCompletions` runs are allowed per `seconds`.
    -- 0 (the default) means a single run per window.
    local allowed = math.max(1, cd.maxCompletions or 0)
    local start   = e.windowStart or e.lastCompleted or 0
    local elapsed = OQ.now() - start

    if elapsed >= seconds then return 0 end               -- window expired
    if (e.windowCount or e.completions or 0) < allowed then return 0 end

    return seconds - elapsed
end

--- Book a completion against the mission's rolling cooldown window.
function OQ.Progression.registerCompletion(entry, mission)
    local cd      = mission.cooldown or {}
    local now     = OQ.now()
    local seconds = cd.seconds or 0

    entry.completions   = (entry.completions or 0) + 1
    entry.lastCompleted = now

    if cd.type == 'none' or cd.type == 'infinite' or seconds <= 0 then
        entry.windowStart = now
        entry.windowCount = 1
        return
    end

    if now - (entry.windowStart or 0) >= seconds then
        entry.windowStart = now
        entry.windowCount = 1
    else
        entry.windowCount = (entry.windowCount or 0) + 1
    end
end

-------------------------------------------------------------------------------
-- DISCOVERY
-------------------------------------------------------------------------------
function OQ.Progression.discover(src, locationUid)
    local p = OQ.Progression.get(src)
    if not p then return false end
    if p.discovered[locationUid] then return false end
    local loc = OQ.Registry.get('location', locationUid)
    if not loc then return false end

    p.discovered[locationUid] = true
    OQ.DB.addDiscovered(p.identifier, locationUid)
    TriggerClientEvent('oqv2:client:discovered', src, locationUid, loc.name)
    return true
end

-------------------------------------------------------------------------------
-- CLIENT PAYLOAD
-------------------------------------------------------------------------------
function OQ.Progression.buildPayload(src)
    local p = OQ.Progression.get(src)
    if not p then return nil end
    local resolved = OQ.resolveXP(p.xp)

    local progress = {}
    for uid, e in pairs(p.progress) do
        progress[uid] = {
            status        = e.status,
            completions   = e.completions,
            lastCompleted = e.lastCompleted,
            progress      = e.progress,
        }
    end

    local discovered = {}
    for uid in pairs(p.discovered) do discovered[#discovered + 1] = uid end

    return {
        identifier = p.identifier,
        name       = p.name,
        level      = resolved.level,
        xp         = resolved.xp,
        need       = resolved.need,
        percent    = resolved.percent,
        totalXP    = resolved.total,
        maxLevel   = resolved.max,
        completed  = p.completed,
        progress   = progress,
        discovered = discovered,
        active     = p.active,
    }
end

function OQ.Progression.sync(src)
    local payload = OQ.Progression.buildPayload(src)
    if payload then
        TriggerClientEvent('oqv2:client:syncPlayer', src, payload)
    end
end

-------------------------------------------------------------------------------
-- LIFECYCLE
-------------------------------------------------------------------------------
RegisterNetEvent('oqv2:server:playerReady', function()
    local src = source
    local p = OQ.Progression.load(src)
    if not p then
        OQ.debug('playerReady but no ESX player yet for', src)
        return
    end
    TriggerClientEvent('oqv2:client:syncWorld', src, OQ.Server.buildWorldPayload())
    OQ.Progression.sync(src)
end)

AddEventHandler('esx:playerLoaded', function(src)
    CreateThread(function()
        Wait(2500)
        if not GetPlayerName(src) then return end
        OQ.Progression.load(src)
        TriggerClientEvent('oqv2:client:syncWorld', src, OQ.Server.buildWorldPayload())
        OQ.Progression.sync(src)
    end)
end)

AddEventHandler('playerDropped', function()
    OQ.Progression.unload(source)
end)

-- periodic save (crash safety)
CreateThread(function()
    while true do
        Wait(300000) -- 5 min
        for src, p in pairs(cache) do
            if GetPlayerName(src) then
                OQ.DB.savePlayer(p)
            else
                cache[src] = nil
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= OQ.resource then return end
    for _, p in pairs(cache) do
        OQ.DB.savePlayer(p)
    end
end)
