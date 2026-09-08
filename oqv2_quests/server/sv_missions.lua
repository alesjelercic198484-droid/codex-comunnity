--[[ OQV2 QUESTS — Mission logic: eligibility, start, progress, rewards
     Made with CodeX Dev. ]]

OQ.Missions = {}

-------------------------------------------------------------------------------
-- WORLD CLOCK (clients report the in-game hour so schedules work server side)
-------------------------------------------------------------------------------
local gameHour, lastHourSync = 12, 0

RegisterNetEvent('oqv2:server:timeSync', function(hour)
    hour = tonumber(hour)
    if not hour or hour < 0 or hour > 23 then return end
    local now = GetGameTimer()
    if now - lastHourSync < 15000 then return end
    lastHourSync = now
    gameHour = math.floor(hour)
end)

function OQ.Missions.hour()
    return gameHour
end

-------------------------------------------------------------------------------
-- ELIGIBILITY
-------------------------------------------------------------------------------
--- @return boolean ok, string|nil reasonKey, table|nil vars
function OQ.Missions.canStart(src, mission)
    if not mission or not mission.enabled then
        return false, 'mission_disabled'
    end

    local p = OQ.Progression.get(src)
    if not p then return false, 'generic_error' end

    -- already running something?
    if p.active and p.active.uid == mission.uid then
        return false, 'mission_already_active'
    end
    if p.active then
        return false, 'mission_limit'
    end

    -- level
    if Config.Progression.enabled and mission.requiredLevel > 0 and p.level < mission.requiredLevel then
        return false, 'mission_level', { level = mission.requiredLevel }
    end

    -- prerequisites
    for _, uid in ipairs(mission.prerequisites or {}) do
        if not OQ.Progression.isCompleted(src, uid) then
            local dep = OQ.Registry.get('mission', uid)
            return false, 'mission_prereq', { name = dep and dep.name or uid }
        end
    end

    -- restriction
    local rs  = mission.restriction or { type = 'all' }
    local job = OQ.Server.getJob(src)
    if rs.type == 'job' then
        if not job or job.name ~= rs.job or (job.grade or 0) < (rs.grade or 0) then
            return false, 'mission_job', { job = rs.job }
        end
    elseif rs.type == 'gang' or rs.type == 'business' then
        local target = rs.gang or rs.job
        if not job or job.name ~= target then
            return false, 'mission_gang', { gang = target }
        end
    elseif rs.type == 'civilian' then
        if job and job.name ~= 'unemployed' and job.name ~= 'civilian' then
            return false, 'mission_civilian'
        end
    elseif rs.type == 'level' then
        if p.level < (rs.level or 0) then
            return false, 'mission_level', { level = rs.level }
        end
    end

    -- schedule
    if mission.schedule and mission.schedule.enabled then
        if not OQ.hourInRange(gameHour, mission.schedule.from, mission.schedule.to) then
            return false, 'mission_schedule', { from = mission.schedule.from, to = mission.schedule.to }
        end
    end

    -- cooldown
    local left = OQ.Progression.cooldownLeft(src, mission)
    if left == -1 then
        return false, 'mission_locked'
    elseif left > 0 then
        return false, 'mission_cooldown', { time = OQ.humanDuration(left) }
    end

    -- start requirements (items / money) — checked but not consumed here
    local req = mission.requirements or {}
    for _, item in ipairs(req.items or {}) do
        local have = OQ.Server.itemCount(src, item.name)
        if have < item.count then
            return false, 'need_items', { count = item.count - have, item = item.name }
        end
    end
    if (req.money or 0) > 0 and OQ.Server.getMoney(src, 'money') < req.money then
        return false, 'need_money', { amount = req.money }
    end

    return true
end

--- Build the mission list shown when a player interacts with a location.
function OQ.Missions.listForLocation(src, locationUid)
    local loc = OQ.Registry.get('location', locationUid)
    if not loc or not loc.enabled then return {} end

    local out = {}
    for _, uid in ipairs(loc.missions or {}) do
        local mission = OQ.Registry.get('mission', uid)
        if mission and mission.enabled then
            local ok, reason, vars = OQ.Missions.canStart(src, mission)
            local entry = OQ.Progression.entry(src, uid, false)
            out[#out + 1] = {
                uid           = mission.uid,
                name          = mission.name,
                description   = mission.description,
                icon          = mission.icon,
                category      = mission.category,
                requiredLevel = mission.requiredLevel,
                xpReward      = mission.xpReward + (mission.rewards.xp or 0),
                rewards       = mission.rewards,
                requirements  = mission.requirements,
                objectives    = mission.objectives,
                cooldown      = mission.cooldown,
                available     = ok,
                reason        = (not ok) and OQ.L(reason, vars) or nil,
                completions   = entry and entry.completions or 0,
            }
        end
    end
    return out
end

-------------------------------------------------------------------------------
-- START
-------------------------------------------------------------------------------

--- True when the player stands close enough to any of the location's points.
function OQ.Missions.nearLocation(src, loc)
    if not loc then return true end
    local points = loc.points or {}
    if #points == 0 then return true end

    local coords  = GetEntityCoords(GetPlayerPed(src))
    local nearest = math.huge
    for _, pt in ipairs(points) do
        nearest = math.min(nearest, #(coords - vec3(pt.x, pt.y, pt.z)))
    end
    return nearest <= (Config.Security.maxDistanceToLocation + 8.0)
end

function OQ.Missions.start(src, missionUid, locationUid)
    local mission = OQ.Registry.get('mission', missionUid)
    if not mission then return false, OQ.L('mission_disabled') end

    -- Eligibility first, so the player gets the useful message
    -- ("already on a mission", "level 5 required", …) instead of a generic
    -- distance rejection.
    local ok, reason, vars = OQ.Missions.canStart(src, mission)
    if not ok then return false, OQ.L(reason, vars) end

    -- location sanity: the mission must actually be offered here
    if locationUid then
        local loc = OQ.Registry.get('location', locationUid)
        if not loc or not OQ.includes(loc.missions or {}, missionUid) then
            return false, OQ.L('generic_error')
        end
        if not OQ.Missions.nearLocation(src, loc) then
            return false, OQ.L('too_far')
        end
    end

    -- consume start requirements
    local req = mission.requirements or {}
    for _, item in ipairs(req.items or {}) do
        if item.remove then
            if not OQ.Server.removeItem(src, item.name, item.count) then
                return false, OQ.L('need_items', { count = item.count, item = item.name })
            end
        end
    end
    if (req.money or 0) > 0 then
        if not OQ.Server.removeMoney(src, 'money', req.money) then
            return false, OQ.L('need_money', { amount = req.money })
        end
    end

    -- build runtime state
    local objectives = {}
    for _, obj in ipairs(mission.objectives) do
        objectives[#objectives + 1] = {
            id       = obj.id,
            type     = obj.type,
            label    = obj.label,
            item     = obj.item,
            model    = obj.model,
            coords   = obj.coords,
            radius   = obj.radius,
            duration = obj.duration,
            anim     = obj.anim,
            marker   = obj.marker,
            blip     = obj.blip,
            optional = obj.optional,
            money    = obj.money,
            need     = (obj.type == 'kill') and obj.amount or obj.count,
            have     = 0,
            done     = false,
        }
    end

    local p = OQ.Progression.get(src)
    p.active = {
        uid        = mission.uid,
        name       = mission.name,
        icon       = mission.icon,
        location   = locationUid,
        startedAt  = OQ.now(),
        objectives = objectives,
    }

    local entry = OQ.Progression.entry(src, mission.uid, true)
    entry.status = 'active'
    entry.progress = { objectives = objectives, startedAt = p.active.startedAt, location = locationUid }
    OQ.Progression.saveEntry(src, mission.uid)

    OQ.DB.log(p.identifier, p.name, 'mission_start', { mission = mission.uid, location = locationUid })

    TriggerClientEvent('oqv2:client:missionStarted', src, p.active, {
        title       = mission.alert.title ~= '' and mission.alert.title or mission.name,
        description = mission.alert.description ~= '' and mission.alert.description or mission.description,
        sound       = mission.alert.sound,
        duration    = mission.alert.duration,
    })
    OQ.Progression.sync(src)
    return true, OQ.L('mission_started', { name = mission.name })
end

-------------------------------------------------------------------------------
-- OBJECTIVE PROGRESS
-------------------------------------------------------------------------------
local function findObjective(active, objectiveId)
    for _, obj in ipairs(active.objectives) do
        if obj.id == objectiveId then return obj end
    end
    return nil
end

local function allDone(active)
    for _, obj in ipairs(active.objectives) do
        if not obj.done and not obj.optional then return false end
    end
    return true
end

--- Server-validated objective advance.
--- @param payload table { amount = number, coords = { x,y,z } }
function OQ.Missions.advance(src, missionUid, objectiveId, payload)
    local p = OQ.Progression.get(src)
    if not p or not p.active or p.active.uid ~= missionUid then return false, 'no_active' end

    local obj = findObjective(p.active, objectiveId)
    if not obj or obj.done then return false, 'invalid_objective' end

    payload = payload or {}
    local ped    = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)

    -- position gate for location based objectives
    if obj.coords and (obj.type == 'goto' or obj.type == 'deliver' or obj.type == 'interact' or obj.type == 'wait') then
        local d = #(coords - vec3(obj.coords.x, obj.coords.y, obj.coords.z))
        if d > (obj.radius + Config.Security.maxDistanceToLocation) then
            return false, 'too_far'
        end
    end

    if obj.type == 'collect' or obj.type == 'give_item' or obj.type == 'deliver' then
        local have = OQ.Server.itemCount(src, obj.item)
        if have < (obj.need or 1) then
            return false, 'need_items'
        end
        if obj.type ~= 'collect' then
            if not OQ.Server.removeItem(src, obj.item, obj.need or 1) then
                return false, 'need_items'
            end
        end
        obj.have = obj.need
        obj.done = true

    elseif obj.type == 'pay' then
        if not OQ.Server.removeMoney(src, 'money', obj.money or 0) then
            return false, 'need_money'
        end
        obj.done = true

    elseif obj.type == 'kill' then
        obj.have = math.min((obj.have or 0) + math.max(1, math.floor(tonumber(payload.amount) or 1)), obj.need or 1)
        obj.done = obj.have >= (obj.need or 1)

    else -- goto / interact / wait
        obj.have = obj.need or 1
        obj.done = true
    end

    local entry = OQ.Progression.entry(src, missionUid, true)
    entry.progress.objectives = p.active.objectives
    OQ.Progression.saveEntry(src, missionUid)

    local finished = allDone(p.active)
    TriggerClientEvent('oqv2:client:objectiveUpdate', src, {
        missionUid = missionUid,
        objectives = p.active.objectives,
        completedId = obj.done and obj.id or nil,
        label      = obj.label,
        allDone    = finished,
    })

    return true, finished and 'all_done' or 'ok'
end

-------------------------------------------------------------------------------
-- COMPLETE
-------------------------------------------------------------------------------
function OQ.Missions.complete(src, missionUid)
    local p = OQ.Progression.get(src)
    if not p or not p.active or p.active.uid ~= missionUid then
        return false, OQ.L('generic_error')
    end

    local mission = OQ.Registry.get('mission', missionUid)
    if not mission then return false, OQ.L('generic_error') end

    if not allDone(p.active) then
        return false, OQ.L('objective_all_complete')
    end

    -- Turn-ins happen at the giver: never trust a client that claims to be there.
    if p.active.location then
        local loc = OQ.Registry.get('location', p.active.location)
        if loc and not OQ.Missions.nearLocation(src, loc) then
            return false, OQ.L('too_far')
        end
    end

    -- rewards
    local rw = mission.rewards or {}
    local granted = { money = 0, bank = 0, black = 0, items = {}, xp = 0 }

    if (rw.money or 0) > 0 then
        OQ.Server.addMoney(src, Config.Economy.moneyAccount, rw.money)
        granted.money = rw.money
    end
    if (rw.bank or 0) > 0 then
        OQ.Server.addMoney(src, 'bank', rw.bank)
        granted.bank = rw.bank
    end
    if (rw.black or 0) > 0 then
        OQ.Server.addMoney(src, 'black', rw.black)
        granted.black = rw.black
    end

    for _, item in ipairs(rw.items or {}) do
        if math.random(1, 100) <= (item.chance or 100) then
            if OQ.Server.canCarry(src, item.name, item.count) then
                if OQ.Server.addItem(src, item.name, item.count, item.metadata) then
                    granted.items[#granted.items + 1] = { name = item.name, count = item.count }
                end
            else
                OQ.Server.notify(src, Config.UI.brand, OQ.L('inventory_full'), 'error')
            end
        end
    end

    -- progression
    local xp = (mission.xpReward or 0) + (rw.xp or 0)
    granted.xp = xp
    OQ.Progression.addXP(src, xp)

    -- bookkeeping
    local entry = OQ.Progression.entry(src, missionUid, true)
    entry.status        = 'completed'
    OQ.Progression.registerCompletion(entry, mission)
    entry.progress      = { lastRun = p.active.objectives }
    OQ.Progression.saveEntry(src, missionUid)

    p.completed = (p.completed or 0) + 1
    p.active = nil
    OQ.DB.savePlayer(p)
    OQ.DB.log(p.identifier, p.name, 'mission_complete', { mission = missionUid, rewards = granted })

    TriggerClientEvent('oqv2:client:missionCompleted', src, {
        uid     = missionUid,
        name    = mission.name,
        rewards = granted,
    })
    OQ.Progression.sync(src)

    -- did this unlock anything?
    local unlocked = {}
    for _, m in pairs(OQ.Registry.missions) do
        if m.enabled and OQ.includes(m.prerequisites or {}, missionUid) then
            local ok = true
            for _, dep in ipairs(m.prerequisites) do
                if not OQ.Progression.isCompleted(src, dep) then ok = false break end
            end
            if ok then unlocked[#unlocked + 1] = { uid = m.uid, name = m.name } end
        end
    end
    if #unlocked > 0 then
        TriggerClientEvent('oqv2:client:missionsUnlocked', src, unlocked)
    end

    return true, OQ.L('mission_completed', { name = mission.name })
end

-------------------------------------------------------------------------------
-- ABANDON
-------------------------------------------------------------------------------
function OQ.Missions.abandon(src)
    local p = OQ.Progression.get(src)
    if not p or not p.active then return false end
    local uid  = p.active.uid
    local name = p.active.name

    local entry = OQ.Progression.entry(src, uid, true)
    entry.status   = 'available'
    entry.progress = {}
    OQ.Progression.saveEntry(src, uid)

    p.active = nil
    OQ.DB.log(p.identifier, p.name, 'mission_abandon', { mission = uid })
    TriggerClientEvent('oqv2:client:missionAbandoned', src, uid)
    OQ.Progression.sync(src)
    OQ.Server.notify(src, Config.UI.brand, OQ.L('mission_abandoned', { name = name }), 'warning')
    return true
end

-------------------------------------------------------------------------------
-- CALLBACKS  (ox_lib)
-------------------------------------------------------------------------------
lib.callback.register('oqv2:server:getLocationMissions', function(source, locationUid)
    if OQ.Server.rateLimited(source) then return {} end
    return OQ.Missions.listForLocation(source, locationUid)
end)

lib.callback.register('oqv2:server:startMission', function(source, missionUid, locationUid)
    if OQ.Server.rateLimited(source) then
        return { success = false, message = OQ.L('rate_limited') }
    end
    local ok, message = OQ.Missions.start(source, missionUid, locationUid)
    return { success = ok, message = message }
end)

lib.callback.register('oqv2:server:advanceObjective', function(source, missionUid, objectiveId, payload)
    local ok, code = OQ.Missions.advance(source, missionUid, objectiveId, payload)
    return { success = ok, code = code }
end)

lib.callback.register('oqv2:server:completeMission', function(source, missionUid)
    if OQ.Server.rateLimited(source) then
        return { success = false, message = OQ.L('rate_limited') }
    end
    local ok, message = OQ.Missions.complete(source, missionUid)
    return { success = ok, message = message }
end)

lib.callback.register('oqv2:server:abandonMission', function(source)
    return OQ.Missions.abandon(source)
end)

lib.callback.register('oqv2:server:getJournal', function(source)
    local payload = OQ.Progression.buildPayload(source)
    if not payload then return nil end

    local missions = {}
    for _, m in pairs(OQ.Registry.missions) do
        if m.enabled then
            local ok, reason, vars = OQ.Missions.canStart(source, m)
            local entry = OQ.Progression.entry(source, m.uid, false)
            local left  = OQ.Progression.cooldownLeft(source, m)
            missions[#missions + 1] = {
                uid           = m.uid,
                name          = m.name,
                description   = m.description,
                category      = m.category,
                icon          = m.icon,
                requiredLevel = m.requiredLevel,
                xpReward      = m.xpReward + (m.rewards.xp or 0),
                rewards       = m.rewards,
                objectives    = m.objectives,
                prerequisites = m.prerequisites,
                completions   = entry and entry.completions or 0,
                available     = ok,
                reason        = (not ok) and OQ.L(reason, vars) or nil,
                cooldownLeft  = left > 0 and left or 0,
                locked        = left == -1,
            }
        end
    end

    local locations = {}
    for _, loc in pairs(OQ.Registry.locations) do
        if loc.enabled then
            local discovered = false
            for _, uid in ipairs(payload.discovered) do
                if uid == loc.uid then discovered = true break end
            end
            locations[#locations + 1] = {
                uid        = loc.uid,
                name       = loc.name,
                missions   = loc.missions,
                points     = discovered and loc.points or nil,
                discovered = discovered,
            }
        end
    end

    return { player = payload, missions = missions, locations = locations, branding = OQ.branding }
end)

RegisterNetEvent('oqv2:server:discover', function(locationUid)
    local src = source
    if type(locationUid) ~= 'string' then return end
    OQ.Progression.discover(src, locationUid)
end)
