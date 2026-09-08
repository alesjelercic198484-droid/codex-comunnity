--[[ OQV2 QUESTS — Evil NPC server authority: kills, loot, police alerts
     Made with CodeX Dev. ]]

OQ.Npcs = {}

--- runtime state per hostile group (server side, anti-exploit bookkeeping)
--- state[uid] = { cycle = n, kills = { [src] = count }, loots = { [src] = count }, lastAlert = 0 }
local state = {}

local function getState(uid)
    if not state[uid] then
        state[uid] = { cycle = 1, kills = {}, loots = {}, lastAlert = 0 }
    end
    return state[uid]
end

local function maxUnits(npc)
    return (npc.count or 1) + (npc.companions or 0)
end

--- Distance check: the reporting player must actually be at the scene.
local function nearGroup(src, npc)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    local d = #(coords - vec3(npc.coords.x, npc.coords.y, npc.coords.z))
    return d <= (npc.radius + 120.0)
end

-------------------------------------------------------------------------------
-- KILL REPORT
-------------------------------------------------------------------------------
function OQ.Npcs.reportKill(src, npcUid)
    local npc = OQ.Registry.get('npc', npcUid)
    if not npc or not npc.enabled then return false end
    if not nearGroup(src, npc) then
        OQ.debug('rejected kill report (too far) from', src, npcUid)
        return false
    end

    local st = getState(npcUid)
    st.kills[src] = (st.kills[src] or 0) + 1
    if st.kills[src] > maxUnits(npc) then
        OQ.debug('kill report over cap from', src, npcUid)
        st.kills[src] = maxUnits(npc)
        return false
    end

    -- xp per kill
    if (npc.xp or 0) > 0 then
        OQ.Progression.addXP(src, npc.xp)
    end

    -- feed an active "kill" objective
    local p = OQ.Progression.get(src)
    if p and p.active then
        local mission = OQ.Registry.get('mission', p.active.uid)
        local linked = (not npc.linkedMission) or npc.linkedMission == p.active.uid
        if mission and linked then
            for _, obj in ipairs(p.active.objectives) do
                if obj.type == 'kill' and not obj.done then
                    local matches = (not obj.model) or obj.model == npc.model or obj.model == npcUid
                    if matches then
                        OQ.Missions.advance(src, p.active.uid, obj.id, { amount = 1 })
                        break
                    end
                end
            end
        end
    end

    return true
end

-------------------------------------------------------------------------------
-- LOOT
-------------------------------------------------------------------------------
function OQ.Npcs.loot(src, npcUid)
    local npc = OQ.Registry.get('npc', npcUid)
    if not npc or not npc.enabled then
        return { success = false, message = OQ.L('generic_error') }
    end
    if not nearGroup(src, npc) then
        return { success = false, message = OQ.L('too_far') }
    end

    local st = getState(npcUid)
    st.loots[src] = (st.loots[src] or 0) + 1
    if st.loots[src] > maxUnits(npc) then
        return { success = false, message = OQ.L('npc_nothing') }
    end

    local received = {}

    for _, item in ipairs(npc.loot or {}) do
        if math.random(1, 100) <= (item.chance or 50) then
            if OQ.Server.canCarry(src, item.name, item.count) then
                if OQ.Server.addItem(src, item.name, item.count) then
                    received[#received + 1] = { name = item.name, count = item.count }
                end
            end
        end
    end

    local money = 0
    if (npc.money.max or 0) > 0 then
        money = math.random(npc.money.min or 0, npc.money.max)
        if money > 0 then
            OQ.Server.addMoney(src, 'money', money)
        end
    end

    if #received == 0 and money == 0 then
        return { success = true, empty = true, message = OQ.L('npc_nothing') }
    end

    local p = OQ.Progression.get(src)
    if p then
        OQ.DB.log(p.identifier, p.name, 'npc_loot', { npc = npcUid, items = received, money = money })
    end

    return { success = true, items = received, money = money, message = OQ.L('npc_looted') }
end

-------------------------------------------------------------------------------
-- POLICE ALERT
-------------------------------------------------------------------------------
function OQ.Npcs.alertPolice(src, npcUid, coords)
    local npc = OQ.Registry.get('npc', npcUid)
    if not npc or not npc.alertPolice then return end

    local st = getState(npcUid)
    local now = GetGameTimer()
    if now - (st.lastAlert or 0) < 60000 then return end
    st.lastAlert = now

    if math.random(1, 100) > (Config.EvilNPC.policeAlertChance or 100) then return end

    local dispatch = Config.EvilNPC.dispatchExport
    if type(dispatch) == 'table' and dispatch.resource and dispatch.method then
        local ok, err = pcall(function()
            exports[dispatch.resource][dispatch.method](nil, {
                title  = 'Shots fired',
                coords = coords,
                source = src,
            })
        end)
        if not ok then OQ.warn('dispatch export failed: ' .. tostring(err)) end
        return
    end

    -- default: notify on-duty police
    for _, playerId in ipairs(GetPlayers()) do
        playerId = tonumber(playerId)
        local job = OQ.Server.getJob(playerId)
        if job and (job.name == 'police' or job.name == 'sheriff' or job.name == 'ambulance') then
            OQ.Server.notify(playerId, '911', OQ.L('police_alerted'), 'error', 8000)
            TriggerClientEvent('oqv2:client:policeBlip', playerId, coords)
        end
    end
end

-------------------------------------------------------------------------------
-- RESET (called when a group respawns)
-------------------------------------------------------------------------------
function OQ.Npcs.resetGroup(npcUid)
    local st = getState(npcUid)
    st.cycle = st.cycle + 1
    st.kills = {}
    st.loots = {}
end

-------------------------------------------------------------------------------
-- NET
-------------------------------------------------------------------------------
RegisterNetEvent('oqv2:server:npcKilled', function(npcUid)
    local src = source
    if type(npcUid) ~= 'string' then return end
    OQ.Npcs.reportKill(src, npcUid)
end)

RegisterNetEvent('oqv2:server:npcAlert', function(npcUid, coords)
    local src = source
    if type(npcUid) ~= 'string' or type(coords) ~= 'table' then return end
    OQ.Npcs.alertPolice(src, npcUid, coords)
end)

RegisterNetEvent('oqv2:server:npcRespawned', function(npcUid)
    if type(npcUid) ~= 'string' then return end
    OQ.Npcs.resetGroup(npcUid)
end)

lib.callback.register('oqv2:server:lootNpc', function(source, npcUid)
    if OQ.Server.rateLimited(source) then
        return { success = false, message = OQ.L('rate_limited') }
    end
    return OQ.Npcs.loot(source, npcUid)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, st in pairs(state) do
        st.kills[src] = nil
        st.loots[src] = nil
    end
end)
