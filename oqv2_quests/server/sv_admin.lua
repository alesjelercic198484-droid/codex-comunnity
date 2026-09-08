--[[ OQV2 QUESTS — Admin backend for the /oqv2 NUI
     Every callback re-checks permissions server side. Made with CodeX Dev. ]]

OQ.Admin = {}

-------------------------------------------------------------------------------
-- GUARD
-------------------------------------------------------------------------------
local function guard(src)
    local allowed, reason = OQ.Server.isAdmin(src)
    if not allowed then
        if Config.Admin.logDenied then
            OQ.warn(('unauthorised admin action from %s (%s)'):format(GetPlayerName(src) or '?', src))
            OQ.DB.log(OQ.Server.getIdentifier(src), OQ.Server.getName(src), 'admin_denied', reason)
        end
        return false
    end
    return true
end

local function adminLog(src, action, detail)
    OQ.DB.log(OQ.Server.getIdentifier(src), OQ.Server.getName(src), action, detail)
end

-------------------------------------------------------------------------------
-- SNAPSHOT (everything the panel needs in one round trip)
-------------------------------------------------------------------------------
local function onlinePlayers()
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local xPlayer = OQ.Server.getPlayer(id)
        if xPlayer then
            local prog = OQ.Progression.get(id, false)
            local resolved = prog and OQ.resolveXP(prog.xp) or { level = 1, xp = 0, need = 0, percent = 0, total = 0 }
            local job = OQ.Server.getJob(id)
            out[#out + 1] = {
                source     = id,
                name       = xPlayer.getName and xPlayer.getName() or GetPlayerName(id),
                identifier = xPlayer.identifier,
                job        = job and job.name or 'unknown',
                grade      = job and job.grade or 0,
                level      = resolved.level,
                xp         = resolved.total,
                percent    = resolved.percent,
                active     = prog and prog.active and prog.active.name or nil,
                completed  = prog and prog.completed or 0,
            }
        end
    end
    table.sort(out, function(a, b) return a.source < b.source end)
    return out
end

function OQ.Admin.snapshot(src)
    local stats = OQ.DB.globalStats()

    local enabledMissions, enabledLocations, enabledNpcs = 0, 0, 0
    for _, m in pairs(OQ.Registry.missions)  do if m.enabled then enabledMissions  = enabledMissions + 1 end end
    for _, l in pairs(OQ.Registry.locations) do if l.enabled then enabledLocations = enabledLocations + 1 end end
    for _, n in pairs(OQ.Registry.npcs)      do if n.enabled then enabledNpcs      = enabledNpcs + 1 end end

    return {
        branding  = OQ.branding,
        ui        = Config.UI,
        schema    = {
            objectiveTypes   = OQ.Schema.objectiveTypes,
            restrictionTypes = OQ.Schema.restrictionTypes,
            repeatTypes      = OQ.Schema.repeatTypes,
            entityTypes      = OQ.Schema.entityTypes,
            difficulties     = OQ.Schema.difficulties,
            categories       = OQ.Schema.categories,
            cooldownPresets  = Config.CooldownPresets,
            defaults         = {
                mission   = OQ.Schema.mission,
                location  = OQ.Schema.location,
                npc       = OQ.Schema.evilNpc,
                objective = OQ.Schema.objective,
            },
        },
        missions  = OQ.Registry.list('mission'),
        locations = OQ.Registry.list('location'),
        npcs      = OQ.Registry.list('npc'),
        players   = onlinePlayers(),
        logs      = OQ.DB.fetchLogs(80),
        leaderboard = OQ.DB.leaderboard(15),
        stats = {
            missions        = OQ.count(OQ.Registry.missions),
            missionsEnabled = enabledMissions,
            locations       = OQ.count(OQ.Registry.locations),
            locationsEnabled= enabledLocations,
            npcs            = OQ.count(OQ.Registry.npcs),
            npcsEnabled     = enabledNpcs,
            playersTracked  = stats.players,
            completions     = stats.completions,
            activeRuns      = stats.active,
            topMission      = stats.topMission,
            online          = #GetPlayers(),
            dbReady         = OQ.DB.isReady(),
        },
        config = {
            locale       = Config.Locale,
            progression  = Config.Progression.enabled,
            maxLevel     = Config.Progression.maxLevel,
            evilNpc      = Config.EvilNPC.enabled,
            journal      = Config.Journal.enabled,
            useDatabase  = Config.UseDatabase,
        },
    }
end

-------------------------------------------------------------------------------
-- SAVE / DELETE
-------------------------------------------------------------------------------
local NORMALIZERS = {
    mission  = { norm = OQ.Schema.normalizeMission,  validate = OQ.Schema.validateMission },
    location = { norm = OQ.Schema.normalizeLocation, validate = OQ.Schema.validateLocation },
    npc      = { norm = OQ.Schema.normalizeEvilNpc,  validate = OQ.Schema.validateEvilNpc },
}

function OQ.Admin.save(src, kind, payload)
    local handler = NORMALIZERS[kind]
    if not handler then return { success = false, errors = { 'Unknown entity type' } } end
    if type(payload) ~= 'table' then return { success = false, errors = { 'Malformed payload' } } end

    local isNew  = not payload.uid or payload.uid == ''
    local entity = handler.norm(payload)
    entity.meta.createdBy = entity.meta.createdBy ~= 'config' and OQ.Server.getName(src) or entity.meta.createdBy
    if isNew then entity.meta.createdBy = OQ.Server.getName(src) end

    local ok, errors = handler.validate(entity)
    if not ok then
        return { success = false, errors = errors }
    end

    -- mission tree sanity
    if kind == 'mission' then
        local sim = {}
        for uid, m in pairs(OQ.Registry.missions) do sim[uid] = m end
        sim[entity.uid] = entity
        local treeOk, cycle = OQ.Schema.checkTree(sim)
        if not treeOk then
            return { success = false, errors = { 'Circular prerequisite chain: ' .. tostring(cycle) } }
        end
    end

    local saved, err = OQ.DB.upsert(kind, entity)
    if not saved then
        return { success = false, errors = { err or 'Database error' } }
    end

    OQ.Registry.set(kind, entity)
    adminLog(src, 'admin_save_' .. kind, { uid = entity.uid, name = entity.name, new = isNew })
    OQ.Server.broadcastWorld(-1)

    return { success = true, uid = entity.uid, entity = entity }
end

function OQ.Admin.delete(src, kind, uid)
    if not NORMALIZERS[kind] then return { success = false, errors = { 'Unknown entity type' } } end
    if type(uid) ~= 'string' or uid == '' then return { success = false, errors = { 'Missing uid' } } end

    local entity = OQ.Registry.get(kind, uid)
    if not entity then return { success = false, errors = { 'Not found' } } end

    -- cleanup references
    if kind == 'mission' then
        OQ.DB.deleteMissionProgress(uid)
        for _, loc in pairs(OQ.Registry.locations) do
            local changed, kept = false, {}
            for _, mUid in ipairs(loc.missions or {}) do
                if mUid == uid then changed = true else kept[#kept + 1] = mUid end
            end
            if changed then
                loc.missions = kept
                OQ.DB.upsert('location', loc)
            end
        end
        for _, m in pairs(OQ.Registry.missions) do
            local changed, kept = false, {}
            for _, dep in ipairs(m.prerequisites or {}) do
                if dep == uid then changed = true else kept[#kept + 1] = dep end
            end
            if changed then
                m.prerequisites = kept
                OQ.DB.upsert('mission', m)
            end
        end
        for _, n in pairs(OQ.Registry.npcs) do
            if n.linkedMission == uid then
                n.linkedMission = nil
                OQ.DB.upsert('npc', n)
            end
        end
    end

    local ok, err = OQ.DB.delete(kind, uid)
    if not ok then return { success = false, errors = { err or 'Database error' } } end

    OQ.Registry.remove(kind, uid)
    adminLog(src, 'admin_delete_' .. kind, { uid = uid, name = entity.name })
    OQ.Server.broadcastWorld(-1)
    return { success = true }
end

function OQ.Admin.toggle(src, kind, uid, enabled)
    local entity = OQ.Registry.get(kind, uid)
    if not entity then return { success = false, errors = { 'Not found' } } end
    entity.enabled = enabled and true or false
    OQ.DB.upsert(kind, entity)
    OQ.Registry.set(kind, entity)
    adminLog(src, 'admin_toggle_' .. kind, { uid = uid, enabled = entity.enabled })
    OQ.Server.broadcastWorld(-1)
    return { success = true, enabled = entity.enabled }
end

function OQ.Admin.duplicate(src, kind, uid)
    local entity = OQ.Registry.get(kind, uid)
    if not entity then return { success = false, errors = { 'Not found' } } end
    local copy = OQ.deepCopy(entity)
    copy.uid  = OQ.uid(kind == 'mission' and 'm' or (kind == 'location' and 'loc' or 'npc'))
    copy.name = (copy.name or 'Copy') .. ' (copy)'
    copy.meta = { createdBy = OQ.Server.getName(src), createdAt = OQ.now(), updatedAt = OQ.now() }
    if kind == 'mission' then
        for _, obj in ipairs(copy.objectives or {}) do obj.id = OQ.uid('obj') end
    end
    return OQ.Admin.save(src, kind, copy)
end

-------------------------------------------------------------------------------
-- PLAYER MANAGEMENT
-------------------------------------------------------------------------------
function OQ.Admin.playerAction(src, action, targetSrc, value)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then
        return { success = false, errors = { 'Player is not online' } }
    end
    local prog = OQ.Progression.get(targetSrc)
    if not prog then return { success = false, errors = { 'No progression data' } } end

    if action == 'addxp' then
        OQ.Progression.addXP(targetSrc, tonumber(value) or 0)
    elseif action == 'setlevel' then
        local level = OQ.clamp(math.floor(tonumber(value) or 1), 1, Config.Progression.maxLevel)
        local total = 0
        for i = 1, level - 1 do total = total + OQ.xpForLevel(i) end
        OQ.Progression.setXP(targetSrc, total)
    elseif action == 'resetprogress' then
        OQ.DB.wipeProgress(prog.identifier)
        prog.progress = {}
        prog.active = nil
        prog.completed = 0
        OQ.DB.savePlayer(prog)
        OQ.Progression.sync(targetSrc)
        TriggerClientEvent('oqv2:client:missionAbandoned', targetSrc, nil)
    elseif action == 'cancelmission' then
        OQ.Missions.abandon(targetSrc)
    elseif action == 'startmission' then
        local ok, message = OQ.Missions.start(targetSrc, tostring(value), nil)
        if not ok then return { success = false, errors = { message } } end
    elseif action == 'teleport' then
        local loc = OQ.Registry.get('location', tostring(value))
        if not loc or not loc.points[1] then return { success = false, errors = { 'Location has no points' } } end
        TriggerClientEvent('oqv2:client:teleport', targetSrc, loc.points[1])
    else
        return { success = false, errors = { 'Unknown action' } }
    end

    adminLog(src, 'admin_player_' .. action, { target = prog.identifier, value = value })
    return { success = true }
end

-------------------------------------------------------------------------------
-- IMPORT / EXPORT
-------------------------------------------------------------------------------
function OQ.Admin.export()
    return {
        version   = OQ.version,
        exportedAt= OQ.now(),
        missions  = OQ.Registry.list('mission'),
        locations = OQ.Registry.list('location'),
        npcs      = OQ.Registry.list('npc'),
    }
end

function OQ.Admin.import(src, payload)
    if type(payload) ~= 'table' then return { success = false, errors = { 'Malformed import' } } end
    local imported, failed = 0, 0
    local sets = {
        { kind = 'mission',  list = payload.missions  or {} },
        { kind = 'location', list = payload.locations or {} },
        { kind = 'npc',      list = payload.npcs      or {} },
    }
    for _, set in ipairs(sets) do
        for _, raw in ipairs(set.list) do
            local res = OQ.Admin.save(src, set.kind, raw)
            if res.success then imported = imported + 1 else failed = failed + 1 end
        end
    end
    adminLog(src, 'admin_import', { imported = imported, failed = failed })
    return { success = true, imported = imported, failed = failed }
end

-------------------------------------------------------------------------------
-- CALLBACKS
-------------------------------------------------------------------------------
lib.callback.register('oqv2:admin:isAdmin', function(source)
    return OQ.Server.isAdmin(source)
end)

lib.callback.register('oqv2:admin:snapshot', function(source)
    if not guard(source) then return nil end
    return OQ.Admin.snapshot(source)
end)

lib.callback.register('oqv2:admin:save', function(source, kind, payload)
    if not guard(source) then return { success = false, errors = { OQ.L('panel_denied') } } end
    return OQ.Admin.save(source, kind, payload)
end)

lib.callback.register('oqv2:admin:delete', function(source, kind, uid)
    if not guard(source) then return { success = false, errors = { OQ.L('panel_denied') } } end
    return OQ.Admin.delete(source, kind, uid)
end)

lib.callback.register('oqv2:admin:toggle', function(source, kind, uid, enabled)
    if not guard(source) then return { success = false, errors = { OQ.L('panel_denied') } } end
    return OQ.Admin.toggle(source, kind, uid, enabled)
end)

lib.callback.register('oqv2:admin:duplicate', function(source, kind, uid)
    if not guard(source) then return { success = false, errors = { OQ.L('panel_denied') } } end
    return OQ.Admin.duplicate(source, kind, uid)
end)

lib.callback.register('oqv2:admin:playerAction', function(source, action, targetSrc, value)
    if not guard(source) then return { success = false, errors = { OQ.L('panel_denied') } } end
    return OQ.Admin.playerAction(source, action, targetSrc, value)
end)

lib.callback.register('oqv2:admin:export', function(source)
    if not guard(source) then return nil end
    return OQ.Admin.export()
end)

lib.callback.register('oqv2:admin:import', function(source, payload)
    if not guard(source) then return { success = false, errors = { OQ.L('panel_denied') } } end
    return OQ.Admin.import(source, payload)
end)

lib.callback.register('oqv2:admin:reload', function(source)
    if not guard(source) then return { success = false } end
    OQ.Server.loadAll()
    OQ.Server.broadcastWorld(-1)
    adminLog(source, 'admin_reload', {})
    return { success = true, message = OQ.L('reloaded') }
end)

lib.callback.register('oqv2:admin:logs', function(source, limit)
    if not guard(source) then return {} end
    return OQ.DB.fetchLogs(limit or 100)
end)
