--[[ OQV2 QUESTS — Data model, defaults & validation | Made with CodeX Dev. ]]

OQ = OQ or {}
OQ.Schema = {}

-------------------------------------------------------------------------------
-- ENUMS (also exported to the NUI so dropdowns stay in sync with the backend)
-------------------------------------------------------------------------------
OQ.Schema.objectiveTypes = {
    { value = 'give_item',   label = 'Hand over item',    icon = 'box-open' },
    { value = 'collect',     label = 'Collect item',      icon = 'hand-holding' },
    { value = 'deliver',     label = 'Deliver to point',  icon = 'truck-fast' },
    { value = 'goto',        label = 'Go to location',    icon = 'location-dot' },
    { value = 'kill',        label = 'Eliminate targets', icon = 'crosshairs' },
    { value = 'interact',    label = 'Interact / animate',icon = 'hands' },
    { value = 'pay',         label = 'Pay money',         icon = 'money-bill' },
    { value = 'wait',        label = 'Timed task',        icon = 'hourglass-half' },
}

OQ.Schema.restrictionTypes = {
    { value = 'all',       label = 'Everyone' },
    { value = 'civilian',  label = 'Civilians only' },
    { value = 'job',       label = 'Specific job' },
    { value = 'gang',      label = 'Specific gang' },
    { value = 'business',  label = 'Business / society' },
    { value = 'level',     label = 'Level gated' },
}

OQ.Schema.repeatTypes = {
    { value = 'none',    label = 'One time only' },
    { value = 'hourly',  label = 'Every hour' },
    { value = 'daily',   label = 'Daily' },
    { value = 'weekly',  label = 'Weekly' },
    { value = 'monthly', label = 'Monthly' },
    { value = 'custom',  label = 'Custom cooldown' },
    { value = 'infinite',label = 'Unlimited' },
}

OQ.Schema.entityTypes = {
    { value = 'ped',    label = 'NPC (ped)' },
    { value = 'object', label = 'Object / prop' },
    { value = 'marker', label = 'Marker only' },
}

OQ.Schema.difficulties = {
    { value = 'easy',   label = 'Easy',   accuracy = 25, health = 150, armour = 0 },
    { value = 'normal', label = 'Normal', accuracy = 45, health = 200, armour = 25 },
    { value = 'hard',   label = 'Hard',   accuracy = 65, health = 250, armour = 75 },
    { value = 'brutal', label = 'Brutal', accuracy = 85, health = 400, armour = 150 },
}

OQ.Schema.categories = {
    'general', 'delivery', 'crime', 'legal', 'gang', 'story', 'event', 'daily',
}

-------------------------------------------------------------------------------
-- DEFAULT SHAPES
-------------------------------------------------------------------------------
OQ.Schema.mission = {
    uid          = '',
    name         = 'New mission',
    description  = '',
    category     = 'general',
    icon         = 'scroll',
    enabled      = true,
    order        = 0,

    -- progression
    requiredLevel = 0,
    xpReward      = 100,
    prerequisites = {},         -- { missionUid, ... }

    -- requirements the player must satisfy to START
    requirements = {
        items  = {},            -- { { name = 'water', count = 2, remove = true }, ... }
        money  = 0,
        job    = nil,           -- { name = 'police', grade = 0 }
        gang   = nil,
        licence= nil,
    },

    -- what the player must DO
    objectives = {},            -- see OQ.Schema.objective

    -- what the player GETS
    rewards = {
        money  = 0,
        bank   = 0,
        black  = 0,
        items  = {},            -- { { name = 'bandage', count = 3, chance = 100 } }
        xp     = 0,             -- extra xp on top of xpReward (kept for flexibility)
    },

    -- access rules
    restriction = {
        type   = 'all',
        job    = nil,
        grade  = 0,
        gang   = nil,
        level  = 0,
    },

    -- repetition
    cooldown = {
        type    = 'none',
        seconds = 0,
        maxCompletions = 0,     -- 0 = unlimited within the cooldown window
    },

    -- player facing alert
    alert = {
        title       = '',
        description = '',
        sound       = 'none',
        duration    = 6000,
    },

    -- time restriction (in-game hours)
    schedule = { enabled = false, from = 0, to = 24 },

    meta = { createdBy = 'config', createdAt = 0, updatedAt = 0 },
}

OQ.Schema.objective = {
    id        = '',
    type      = 'goto',
    label     = '',
    item      = nil,
    count     = 1,
    money     = 0,
    coords    = nil,            -- { x, y, z }
    radius    = 2.0,
    duration  = 5000,
    anim      = nil,            -- { dict = '', clip = '', flag = 49 }
    model     = nil,            -- for kill objectives
    amount    = 1,
    marker    = true,
    blip      = true,
    optional  = false,
}

OQ.Schema.location = {
    uid         = '',
    name        = 'New location',
    description = '',
    enabled     = true,

    entity = {
        type    = 'ped',
        model   = 'a_m_m_business_01',
        scenario= nil,                       -- e.g. 'WORLD_HUMAN_CLIPBOARD'
        anim    = nil,                       -- { dict, clip }
        freeze  = true,
        invincible = true,
        ignore  = true,
    },

    -- one or many spots; `rotate` makes the NPC hop between them
    points  = {},                            -- { { x, y, z, w }, ... }
    rotate  = { enabled = false, interval = 1800 },

    target = {
        label    = 'Talk',
        icon     = 'fa-solid fa-comments',
        distance = 2.0,
    },

    dialogue = {
        title   = 'Hello there',
        text    = 'I might have something for you...',
        accept  = 'Accept',
        decline = 'Leave',
        portrait= nil,
    },

    blip = { enabled = true, sprite = 480, color = 27, scale = 0.8, label = nil, shortRange = true },

    schedule = { enabled = false, from = 0, to = 24 },

    missions = {},                           -- { missionUid, ... }

    meta = { createdBy = 'config', createdAt = 0, updatedAt = 0 },
}

OQ.Schema.evilNpc = {
    uid         = '',
    name        = 'Hostile group',
    enabled     = true,
    model       = 'g_m_y_ballasout_01',
    count       = 3,
    companions  = 0,
    weapons     = { 'WEAPON_PISTOL' },
    coords      = { x = 0.0, y = 0.0, z = 0.0 },
    radius      = 25.0,
    trigger     = { type = 'proximity', distance = 90.0 },
    difficulty  = 'normal',
    aggression  = 75,
    alertPolice = true,
    respawn     = 300,
    loot        = {},                        -- { { name = 'weapon_pistol_ammo', count = 12, chance = 40 } }
    money       = { min = 0, max = 0 },
    xp          = 25,
    linkedMission = nil,
    meta        = { createdBy = 'config', createdAt = 0, updatedAt = 0 },
}

-------------------------------------------------------------------------------
-- NORMALISERS  (fill defaults + coerce types; used before saving / sending)
-------------------------------------------------------------------------------
local function num(v, fallback)
    return tonumber(v) or fallback or 0
end

local function bool(v, fallback)
    if v == nil then return fallback and true or false end
    if type(v) == 'string' then return v == 'true' or v == '1' end
    return v and true or false
end

function OQ.Schema.normalizeObjective(obj, index)
    obj = OQ.defaults(obj, OQ.Schema.objective)
    if obj.id == '' or obj.id == nil then obj.id = OQ.uid('obj') end
    obj.type     = tostring(obj.type or 'goto')
    local lbl = OQ.trim(obj.label)
    obj.label    = (lbl ~= '' and lbl ~= 'Objective') and lbl or ('Objective #' .. (index or 1))
    obj.count    = math.max(1, math.floor(num(obj.count, 1)))
    obj.amount   = math.max(1, math.floor(num(obj.amount, 1)))
    obj.money    = math.max(0, math.floor(num(obj.money, 0)))
    obj.radius   = math.max(0.5, num(obj.radius, 2.0))
    obj.duration = math.max(0, math.floor(num(obj.duration, 5000)))
    obj.optional = bool(obj.optional, false)
    obj.marker   = bool(obj.marker, true)
    obj.blip     = bool(obj.blip, true)
    if obj.coords then
        obj.coords = { x = num(obj.coords.x), y = num(obj.coords.y), z = num(obj.coords.z) }
    end
    if obj.item == '' then obj.item = nil end
    if obj.model == '' then obj.model = nil end
    return obj
end

function OQ.Schema.normalizeMission(mission)
    mission = OQ.defaults(mission, OQ.Schema.mission)
    if mission.uid == '' or mission.uid == nil then mission.uid = OQ.uid('m') end
    mission.name          = OQ.trim(mission.name)
    mission.description   = tostring(mission.description or '')
    mission.category      = tostring(mission.category or 'general')
    mission.enabled       = bool(mission.enabled, true)
    mission.order         = math.floor(num(mission.order, 0))
    mission.requiredLevel = math.max(0, math.floor(num(mission.requiredLevel, 0)))
    mission.xpReward      = math.max(0, math.floor(num(mission.xpReward, 0)))

    -- prerequisites: unique, no self reference
    local prereq, seen = {}, {}
    for _, uid in ipairs(mission.prerequisites or {}) do
        if type(uid) == 'string' and uid ~= '' and uid ~= mission.uid and not seen[uid] then
            seen[uid] = true
            prereq[#prereq + 1] = uid
        end
    end
    mission.prerequisites = prereq

    -- requirements
    local req = mission.requirements
    req.money = math.max(0, math.floor(num(req.money, 0)))
    local items = {}
    for _, it in ipairs(req.items or {}) do
        if type(it) == 'table' and it.name and it.name ~= '' then
            items[#items + 1] = {
                name   = tostring(it.name),
                count  = math.max(1, math.floor(num(it.count, 1))),
                remove = bool(it.remove, true),
            }
        end
    end
    req.items = items
    if req.job and (req.job == '' or req.job.name == '') then req.job = nil end
    if req.gang and (req.gang == '' or req.gang.name == '') then req.gang = nil end

    -- objectives
    local objectives = {}
    for i, obj in ipairs(mission.objectives or {}) do
        objectives[#objectives + 1] = OQ.Schema.normalizeObjective(obj, i)
    end
    mission.objectives = objectives

    -- rewards
    local rw = mission.rewards
    rw.money = math.max(0, math.floor(num(rw.money, 0)))
    rw.bank  = math.max(0, math.floor(num(rw.bank, 0)))
    rw.black = math.max(0, math.floor(num(rw.black, 0)))
    rw.xp    = math.max(0, math.floor(num(rw.xp, 0)))
    local rewardItems = {}
    for _, it in ipairs(rw.items or {}) do
        if type(it) == 'table' and it.name and it.name ~= '' then
            rewardItems[#rewardItems + 1] = {
                name   = tostring(it.name),
                count  = math.max(1, math.floor(num(it.count, 1))),
                chance = OQ.clamp(math.floor(num(it.chance, 100)), 1, 100),
                metadata = type(it.metadata) == 'table' and it.metadata or nil,
            }
        end
    end
    rw.items = rewardItems

    -- restriction
    local rs = mission.restriction
    rs.type  = tostring(rs.type or 'all')
    rs.grade = math.max(0, math.floor(num(rs.grade, 0)))
    rs.level = math.max(0, math.floor(num(rs.level, 0)))
    if rs.job == '' then rs.job = nil end
    if rs.gang == '' then rs.gang = nil end

    -- cooldown
    local cd = mission.cooldown
    cd.type = tostring(cd.type or 'none')
    if Config.CooldownPresets[cd.type] then
        cd.seconds = Config.CooldownPresets[cd.type]
    else
        cd.seconds = math.max(0, math.floor(num(cd.seconds, 0)))
    end
    cd.maxCompletions = math.max(0, math.floor(num(cd.maxCompletions, 0)))

    -- alert
    mission.alert.duration = math.max(1000, math.floor(num(mission.alert.duration, 6000)))

    -- schedule
    mission.schedule.enabled = bool(mission.schedule.enabled, false)
    mission.schedule.from    = OQ.clamp(math.floor(num(mission.schedule.from, 0)), 0, 24)
    mission.schedule.to      = OQ.clamp(math.floor(num(mission.schedule.to, 24)), 0, 24)

    mission.meta.updatedAt = OQ.now()
    if not mission.meta.createdAt or mission.meta.createdAt == 0 then
        mission.meta.createdAt = OQ.now()
    end
    return mission
end

function OQ.Schema.normalizeLocation(loc)
    loc = OQ.defaults(loc, OQ.Schema.location)
    if loc.uid == '' or loc.uid == nil then loc.uid = OQ.uid('loc') end
    loc.name    = OQ.trim(loc.name)
    loc.enabled = bool(loc.enabled, true)

    loc.entity.type       = tostring(loc.entity.type or 'ped')
    loc.entity.model      = tostring(loc.entity.model or 'a_m_m_business_01')
    loc.entity.freeze     = bool(loc.entity.freeze, true)
    loc.entity.invincible = bool(loc.entity.invincible, true)
    loc.entity.ignore     = bool(loc.entity.ignore, true)
    if loc.entity.scenario == '' then loc.entity.scenario = nil end
    if type(loc.entity.anim) == 'table' and (not loc.entity.anim.dict or loc.entity.anim.dict == '') then
        loc.entity.anim = nil
    end

    local points = {}
    for _, p in ipairs(loc.points or {}) do
        if type(p) == 'table' then
            points[#points + 1] = {
                x = num(p.x), y = num(p.y), z = num(p.z), w = num(p.w or p.heading, 0.0),
            }
        end
    end
    loc.points = points
    loc.rotate.enabled  = bool(loc.rotate.enabled, false)
    loc.rotate.interval = math.max(30, math.floor(num(loc.rotate.interval, 1800)))

    loc.target.distance = OQ.clamp(num(loc.target.distance, 2.0), 0.5, 8.0)
    loc.target.label    = OQ.trim(loc.target.label) ~= '' and loc.target.label or 'Talk'

    loc.blip.enabled = bool(loc.blip.enabled, true)
    loc.blip.sprite  = math.floor(num(loc.blip.sprite, 480))
    loc.blip.color   = math.floor(num(loc.blip.color, 27))
    loc.blip.scale   = OQ.clamp(num(loc.blip.scale, 0.8), 0.2, 2.0)
    loc.blip.shortRange = bool(loc.blip.shortRange, true)
    if not loc.blip.label or loc.blip.label == '' then loc.blip.label = loc.name end

    loc.schedule.enabled = bool(loc.schedule.enabled, false)
    loc.schedule.from    = OQ.clamp(math.floor(num(loc.schedule.from, 0)), 0, 24)
    loc.schedule.to      = OQ.clamp(math.floor(num(loc.schedule.to, 24)), 0, 24)

    local missions, seen = {}, {}
    for _, uid in ipairs(loc.missions or {}) do
        if type(uid) == 'string' and uid ~= '' and not seen[uid] then
            seen[uid] = true
            missions[#missions + 1] = uid
        end
    end
    loc.missions = missions

    loc.meta.updatedAt = OQ.now()
    if not loc.meta.createdAt or loc.meta.createdAt == 0 then loc.meta.createdAt = OQ.now() end
    return loc
end

function OQ.Schema.normalizeEvilNpc(npc)
    npc = OQ.defaults(npc, OQ.Schema.evilNpc)
    if npc.uid == '' or npc.uid == nil then npc.uid = OQ.uid('npc') end
    npc.name        = OQ.trim(npc.name)
    npc.enabled     = bool(npc.enabled, true)
    npc.model       = tostring(npc.model or 'g_m_y_ballasout_01')
    npc.count       = OQ.clamp(math.floor(num(npc.count, 1)), 1, 12)
    npc.companions  = OQ.clamp(math.floor(num(npc.companions, 0)), 0, 8)
    npc.radius      = OQ.clamp(num(npc.radius, 25.0), 2.0, 200.0)
    npc.aggression  = OQ.clamp(math.floor(num(npc.aggression, 75)), 0, 100)
    npc.alertPolice = bool(npc.alertPolice, true)
    npc.respawn     = math.max(0, math.floor(num(npc.respawn, Config.EvilNPC.defaultRespawn)))
    npc.xp          = math.max(0, math.floor(num(npc.xp, 0)))
    npc.difficulty  = tostring(npc.difficulty or 'normal')
    npc.coords      = { x = num(npc.coords and npc.coords.x), y = num(npc.coords and npc.coords.y), z = num(npc.coords and npc.coords.z) }
    npc.trigger.distance = OQ.clamp(num(npc.trigger.distance, 90.0), 10.0, 400.0)

    local weapons = {}
    for _, w in ipairs(npc.weapons or {}) do
        if type(w) == 'string' and w ~= '' then weapons[#weapons + 1] = w:upper() end
    end
    npc.weapons = #weapons > 0 and weapons or { 'WEAPON_PISTOL' }

    local loot = {}
    for _, it in ipairs(npc.loot or {}) do
        if type(it) == 'table' and it.name and it.name ~= '' then
            loot[#loot + 1] = {
                name   = tostring(it.name),
                count  = math.max(1, math.floor(num(it.count, 1))),
                chance = OQ.clamp(math.floor(num(it.chance, 50)), 1, 100),
            }
        end
    end
    npc.loot = loot
    npc.money.min = math.max(0, math.floor(num(npc.money.min, 0)))
    npc.money.max = math.max(npc.money.min, math.floor(num(npc.money.max, 0)))
    if npc.linkedMission == '' then npc.linkedMission = nil end

    npc.meta.updatedAt = OQ.now()
    if not npc.meta.createdAt or npc.meta.createdAt == 0 then npc.meta.createdAt = OQ.now() end
    return npc
end

-------------------------------------------------------------------------------
-- VALIDATION  (returns ok:boolean, errors:string[])
-------------------------------------------------------------------------------
function OQ.Schema.validateMission(mission)
    local errors = {}
    if OQ.trim(mission.name) == '' then errors[#errors + 1] = 'Mission name is required' end
    if #mission.objectives == 0 then errors[#errors + 1] = 'At least one objective is required' end
    for i, obj in ipairs(mission.objectives) do
        local needsItem = obj.type == 'give_item' or obj.type == 'collect' or obj.type == 'deliver'
        if needsItem and (not obj.item or obj.item == '') then
            errors[#errors + 1] = ('Objective #%d (%s) needs an item name'):format(i, obj.type)
        end
        local needsCoords = obj.type == 'goto' or obj.type == 'deliver' or obj.type == 'interact' or obj.type == 'wait'
        if needsCoords and not obj.coords then
            errors[#errors + 1] = ('Objective #%d (%s) needs coordinates'):format(i, obj.type)
        end
        if obj.type == 'pay' and obj.money <= 0 then
            errors[#errors + 1] = ('Objective #%d (pay) needs an amount > 0'):format(i)
        end
    end
    if mission.restriction.type == 'job' and not mission.restriction.job then
        errors[#errors + 1] = 'Job restriction selected but no job set'
    end
    if mission.restriction.type == 'gang' and not mission.restriction.gang then
        errors[#errors + 1] = 'Gang restriction selected but no gang set'
    end
    if mission.cooldown.type == 'custom' and mission.cooldown.seconds <= 0 then
        errors[#errors + 1] = 'Custom cooldown must be greater than 0 seconds'
    end
    return #errors == 0, errors
end

function OQ.Schema.validateLocation(loc)
    local errors = {}
    if OQ.trim(loc.name) == '' then errors[#errors + 1] = 'Location name is required' end
    if #loc.points == 0 then errors[#errors + 1] = 'At least one spawn point is required' end
    if loc.entity.type ~= 'marker' and (not loc.entity.model or loc.entity.model == '') then
        errors[#errors + 1] = 'A model is required for ped/object locations'
    end
    if #loc.missions == 0 then errors[#errors + 1] = 'Link at least one mission to this location' end
    return #errors == 0, errors
end

function OQ.Schema.validateEvilNpc(npc)
    local errors = {}
    if OQ.trim(npc.name) == '' then errors[#errors + 1] = 'Name is required' end
    if npc.coords.x == 0 and npc.coords.y == 0 and npc.coords.z == 0 then
        errors[#errors + 1] = 'Spawn coordinates are required'
    end
    if npc.count < 1 then errors[#errors + 1] = 'Count must be at least 1' end
    return #errors == 0, errors
end

--- Detect a circular dependency in the mission prerequisite tree.
---@param missions table<string, table>
---@return boolean ok, string|nil cycleDescription
function OQ.Schema.checkTree(missions)
    local state = {}   -- nil = unvisited, 1 = visiting, 2 = done
    local path = {}

    local function visit(uid)
        if state[uid] == 2 then return true end
        if state[uid] == 1 then
            path[#path + 1] = uid
            return false
        end
        local mission = missions[uid]
        if not mission then return true end
        state[uid] = 1
        path[#path + 1] = uid
        for _, dep in ipairs(mission.prerequisites or {}) do
            if not visit(dep) then return false end
        end
        state[uid] = 2
        path[#path] = nil
        return true
    end

    for uid in pairs(missions) do
        path = {}
        if not visit(uid) then
            return false, table.concat(path, ' → ')
        end
    end
    return true, nil
end
