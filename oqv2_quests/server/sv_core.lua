--[[ OQV2 QUESTS — Server core: framework bridge, registry, permissions
     Made with CodeX Dev. ]]

OQ.Server = OQ.Server or {}

-------------------------------------------------------------------------------
-- FRAMEWORK BRIDGE (ESX)
-------------------------------------------------------------------------------
ESX = nil

CreateThread(function()
    local attempts = 0
    while ESX == nil do
        local ok, obj = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and obj then
            ESX = obj
            break
        end
        attempts = attempts + 1
        if attempts == 20 then
            OQ.error('es_extended not found — make sure ESX starts before oqv2_quests.')
        end
        Wait(500)
    end
    OQ.debug('ESX bridge ready')
end)

--- @return table|nil xPlayer
function OQ.Server.getPlayer(src)
    if not ESX then return nil end
    return ESX.GetPlayerFromId(src)
end

function OQ.Server.getIdentifier(src)
    local xPlayer = OQ.Server.getPlayer(src)
    return xPlayer and xPlayer.identifier or nil
end

function OQ.Server.getName(src)
    local xPlayer = OQ.Server.getPlayer(src)
    if xPlayer then
        return xPlayer.getName and xPlayer.getName() or (GetPlayerName(src) or 'Unknown')
    end
    return GetPlayerName(src) or 'Unknown'
end

function OQ.Server.getJob(src)
    local xPlayer = OQ.Server.getPlayer(src)
    if not xPlayer then return nil end
    return xPlayer.getJob and xPlayer.getJob() or xPlayer.job
end

function OQ.Server.notify(src, title, description, ntype, duration)
    Config.Notify(src, {
        title       = title,
        description = description,
        type        = ntype or 'inform',
        duration    = duration or 5000,
        position    = 'top-right',
    })
end

-------------------------------------------------------------------------------
-- MONEY
-------------------------------------------------------------------------------
local ACCOUNTS = { money = 'money', cash = 'money', bank = 'bank', black = 'black_money', black_money = 'black_money' }

function OQ.Server.addMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local xPlayer = OQ.Server.getPlayer(src)
    if not xPlayer then return false end
    local acc = ACCOUNTS[account] or 'money'
    if acc == 'money' then
        xPlayer.addMoney(amount, 'oqv2_quests')
    else
        xPlayer.addAccountMoney(acc, amount, 'oqv2_quests')
    end
    return true
end

function OQ.Server.getMoney(src, account)
    local xPlayer = OQ.Server.getPlayer(src)
    if not xPlayer then return 0 end
    local acc = ACCOUNTS[account] or 'money'
    if acc == 'money' then return xPlayer.getMoney() end
    local a = xPlayer.getAccount(acc)
    return a and a.money or 0
end

function OQ.Server.removeMoney(src, account, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local xPlayer = OQ.Server.getPlayer(src)
    if not xPlayer then return false end
    local acc = ACCOUNTS[account] or 'money'
    if OQ.Server.getMoney(src, acc) < amount then return false end
    if acc == 'money' then
        xPlayer.removeMoney(amount, 'oqv2_quests')
    else
        xPlayer.removeAccountMoney(acc, amount, 'oqv2_quests')
    end
    return true
end

-------------------------------------------------------------------------------
-- INVENTORY (ox_inventory)
-------------------------------------------------------------------------------
function OQ.Server.itemCount(src, item)
    local ok, count = pcall(function()
        return exports.ox_inventory:Search(src, 'count', item)
    end)
    return ok and (tonumber(count) or 0) or 0
end

function OQ.Server.canCarry(src, item, count)
    if not Config.Economy.checkCarry then return true end
    local ok, res = pcall(function()
        return exports.ox_inventory:CanCarryItem(src, item, count)
    end)
    if not ok then return true end
    return res ~= false
end

function OQ.Server.addItem(src, item, count, metadata)
    local ok, res = pcall(function()
        return exports.ox_inventory:AddItem(src, item, count, metadata)
    end)
    if not ok then
        OQ.error(('AddItem failed for "%s": %s'):format(tostring(item), tostring(res)))
        return false
    end
    return res ~= false
end

function OQ.Server.removeItem(src, item, count, metadata)
    local ok, res = pcall(function()
        return exports.ox_inventory:RemoveItem(src, item, count, metadata)
    end)
    if not ok then
        OQ.error(('RemoveItem failed for "%s": %s'):format(tostring(item), tostring(res)))
        return false
    end
    return res ~= false
end

-------------------------------------------------------------------------------
-- REGISTRY (in-memory mirror of the DB)
-------------------------------------------------------------------------------
OQ.Registry = {
    missions  = {},   -- [uid] = mission
    locations = {},   -- [uid] = location
    npcs      = {},   -- [uid] = evilNpc
}

local function indexList(list)
    local out = {}
    for _, v in ipairs(list) do out[v.uid] = v end
    return out
end

function OQ.Registry.list(kind)
    local src = OQ.Registry[kind .. 's'] or {}
    local out = {}
    for _, v in pairs(src) do out[#out + 1] = v end
    table.sort(out, function(a, b)
        local ao, bo = a.order or 0, b.order or 0
        if ao ~= bo then return ao < bo end
        return (a.name or '') < (b.name or '')
    end)
    return out
end

function OQ.Registry.get(kind, uid)
    local src = OQ.Registry[kind .. 's']
    return src and src[uid] or nil
end

function OQ.Registry.set(kind, entity)
    local src = OQ.Registry[kind .. 's']
    if not src then return false end
    src[entity.uid] = entity
    return true
end

function OQ.Registry.remove(kind, uid)
    local src = OQ.Registry[kind .. 's']
    if not src then return false end
    src[uid] = nil
    return true
end

-------------------------------------------------------------------------------
-- SEEDING + LOADING
-------------------------------------------------------------------------------
local function seedIfEmpty()
    if not Config.SeedFromConfig then return end

    local seeds = {
        { kind = 'mission',  cfg = Config.Missions  or {}, norm = OQ.Schema.normalizeMission },
        { kind = 'location', cfg = Config.Locations or {}, norm = OQ.Schema.normalizeLocation },
        { kind = 'npc',      cfg = Config.EvilNpcs  or {}, norm = OQ.Schema.normalizeEvilNpc },
    }

    for _, seed in ipairs(seeds) do
        local existing = OQ.DB.count(seed.kind)
        if existing == 0 and #seed.cfg > 0 then
            local imported = 0
            for _, raw in ipairs(seed.cfg) do
                local entity = seed.norm(OQ.deepCopy(raw))
                entity.meta.createdBy = 'config'
                if OQ.DB.upsert(seed.kind, entity) then imported = imported + 1 end
            end
            OQ.print(('^2seeded %d %s(s) from config^7'):format(imported, seed.kind))
        end
    end
end

function OQ.Server.loadAll()
    if Config.UseDatabase and OQ.DB.isReady() then
        OQ.Registry.missions  = indexList(OQ.DB.fetchAll('mission'))
        OQ.Registry.locations = indexList(OQ.DB.fetchAll('location'))
        OQ.Registry.npcs      = indexList(OQ.DB.fetchAll('npc'))
    else
        -- memory-only fallback: work straight off the config files
        local m, l, n = {}, {}, {}
        for _, raw in ipairs(Config.Missions  or {}) do local e = OQ.Schema.normalizeMission(OQ.deepCopy(raw));  m[e.uid] = e end
        for _, raw in ipairs(Config.Locations or {}) do local e = OQ.Schema.normalizeLocation(OQ.deepCopy(raw)); l[e.uid] = e end
        for _, raw in ipairs(Config.EvilNpcs  or {}) do local e = OQ.Schema.normalizeEvilNpc(OQ.deepCopy(raw));  n[e.uid] = e end
        OQ.Registry.missions, OQ.Registry.locations, OQ.Registry.npcs = m, l, n
    end

    local okTree, cycle = OQ.Schema.checkTree(OQ.Registry.missions)
    if not okTree then
        OQ.warn('circular mission prerequisite detected: ' .. tostring(cycle))
    end

    OQ.print(('^2loaded^7 %d missions, %d locations, %d hostile groups')
        :format(OQ.count(OQ.Registry.missions), OQ.count(OQ.Registry.locations), OQ.count(OQ.Registry.npcs)))
end

-------------------------------------------------------------------------------
-- PUBLIC WORLD PAYLOAD (what clients need to build the world)
-------------------------------------------------------------------------------
--- Strips admin-only / heavy fields before sending to clients.
function OQ.Server.buildWorldPayload()
    local locations = {}
    for _, loc in pairs(OQ.Registry.locations) do
        if loc.enabled then
            locations[#locations + 1] = {
                uid      = loc.uid,
                name     = loc.name,
                entity   = loc.entity,
                points   = loc.points,
                rotate   = loc.rotate,
                target   = loc.target,
                dialogue = loc.dialogue,
                blip     = loc.blip,
                schedule = loc.schedule,
                missions = loc.missions,
            }
        end
    end

    local missions = {}
    for _, m in pairs(OQ.Registry.missions) do
        if m.enabled then
            missions[#missions + 1] = {
                uid           = m.uid,
                name          = m.name,
                description   = m.description,
                category      = m.category,
                icon          = m.icon,
                requiredLevel = m.requiredLevel,
                xpReward      = m.xpReward + (m.rewards.xp or 0),
                prerequisites = m.prerequisites,
                requirements  = m.requirements,
                objectives    = m.objectives,
                rewards       = { money = m.rewards.money, bank = m.rewards.bank, black = m.rewards.black, items = m.rewards.items },
                restriction   = m.restriction,
                cooldown      = m.cooldown,
                alert         = m.alert,
                schedule      = m.schedule,
            }
        end
    end

    local npcs = {}
    if Config.EvilNPC.enabled then
        for _, n in pairs(OQ.Registry.npcs) do
            if n.enabled then
                npcs[#npcs + 1] = {
                    uid = n.uid, name = n.name, model = n.model, count = n.count,
                    companions = n.companions, weapons = n.weapons, coords = n.coords,
                    radius = n.radius, trigger = n.trigger, difficulty = n.difficulty,
                    aggression = n.aggression, alertPolice = n.alertPolice,
                    respawn = n.respawn, linkedMission = n.linkedMission,
                }
            end
        end
    end

    return { missions = missions, locations = locations, npcs = npcs }
end

function OQ.Server.broadcastWorld(target)
    local payload = OQ.Server.buildWorldPayload()
    TriggerClientEvent('oqv2:client:syncWorld', target or -1, payload)
end

-------------------------------------------------------------------------------
-- PERMISSIONS
-------------------------------------------------------------------------------
--- @return boolean allowed, string reason
function OQ.Server.isAdmin(src)
    src = tonumber(src) or 0

    if src == 0 then
        return Config.Admin.allowConsole == true, 'console'
    end

    -- 1. ACE permission
    if Config.Admin.ace and Config.Admin.ace ~= '' then
        if IsPlayerAceAllowed(src, Config.Admin.ace) then return true, 'ace' end
    end

    -- 2. ESX group
    local xPlayer = OQ.Server.getPlayer(src)
    if xPlayer then
        local group = xPlayer.getGroup and xPlayer.getGroup() or xPlayer.group
        if group and OQ.includes(Config.Admin.groups, group) then return true, 'group:' .. group end
    end

    -- 3. Whitelisted identifiers
    if #(Config.Admin.identifiers or {}) > 0 then
        for i = 0, GetNumPlayerIdentifiers(src) - 1 do
            local ident = GetPlayerIdentifier(src, i)
            if ident and OQ.includes(Config.Admin.identifiers, ident) then return true, 'identifier' end
        end
    end

    return false, 'denied'
end

-------------------------------------------------------------------------------
-- RATE LIMIT
-------------------------------------------------------------------------------
local lastEvent, abuse = {}, {}

function OQ.Server.rateLimited(src)
    local now = GetGameTimer()
    local last = lastEvent[src] or 0
    if now - last < (Config.Security.rateLimitMs or 0) then
        abuse[src] = (abuse[src] or 0) + 1
        if abuse[src] == Config.Security.abuseThreshold then
            OQ.warn(('possible abuse from %s (%s) — %d rate limited events')
                :format(GetPlayerName(src) or '?', src, abuse[src]))
            OQ.DB.log(OQ.Server.getIdentifier(src), OQ.Server.getName(src), 'abuse', 'rate limit threshold reached')
            if Config.Security.kickOnAbuse then
                DropPlayer(src, 'OQV2 Quests: suspicious activity detected.')
            end
        end
        return true
    end
    lastEvent[src] = now
    return false
end

AddEventHandler('playerDropped', function()
    local src = source
    lastEvent[src] = nil
    abuse[src] = nil
end)

-------------------------------------------------------------------------------
-- BOOT
-------------------------------------------------------------------------------
AddEventHandler('onResourceStart', function(resource)
    if resource ~= OQ.resource then return end

    CreateThread(function()
        Wait(500)   -- let oxmysql finish connecting
        OQ.print(('^5%s v%s^7 by ^6%s^7'):format(Config.UI.brand, OQ.version, Config.UI.author))
        OQ.print('^5' .. Config.UI.footer .. '^7')

        if Config.UseDatabase then
            if OQ.DB.ensureSchema() then
                seedIfEmpty()
            else
                OQ.warn('database unavailable → falling back to config-only mode')
            end
        end

        OQ.Server.loadAll()

        Wait(1000)
        OQ.Server.broadcastWorld(-1)
    end)
end)
